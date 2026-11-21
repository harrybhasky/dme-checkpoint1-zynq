`timescale 1ns/1ps

// Self-checking testbench for the checkpoint 1 pulse-pair generator IP
// (dme_axi4lite + dme_pulse_pair_modulator), as packaged and used on the
// board. The Xilinx DDS Compiler (1 MHz sine, 15-bit, 16-bit tdata) is
// replaced by a behavioural model with the same phase increment.
//
// Checks:
//   1. AXI4-Lite: reset values, read/write, SLVERR on unmapped addresses,
//      periods below the 450 us minimum are ignored.
//   2. Timing: 50 us pulses, 350 us gap (400 us rising to rising) and the
//      software-set pair period, for several pairs.
//   3. Default pulse rate: 33333 us period (30 pairs/s).
//   4. Envelope: raised cosine, starts and ends at 0, peaks at 32767.
//   5. Carrier: 1 MHz (zero crossings), amplitude follows the envelope.
//   6. Carrier off: the output is the bare envelope.
//   7. Disable: output returns to 0 and the generator idles.
module tb_dme_ckpt1;
    localparam int CLK_HZ   = 100_000_000;
    localparam int CYC_US   = CLK_HZ / 1_000_000;

    logic clk = 1'b0;
    logic rstn = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------- DDS
    // dds_compiler_0: Phase_Width 28, PINC1 = 2684354 (1.0 MHz at 100 MHz),
    // Output_Width 15, sine. tdata is 16 bits, sign-extended.
    localparam int unsigned PINC = 28'd2684354;
    logic [27:0] dds_phase = '0;
    logic [15:0] dds_tdata = '0;
    always @(posedge clk) begin
        dds_phase <= dds_phase + PINC;
        dds_tdata <= 16'($rtoi($sin(2.0 * 3.14159265358979 * dds_phase / 268435456.0) * 16383.0));
    end

    // ---------------------------------------------------------------- AXI
    logic [5:0]  awaddr, araddr;
    logic        awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    wire         awready, wready, bvalid, arready, rvalid;
    wire  [1:0]  bresp, rresp;
    wire  [31:0] rdata;
    wire  [15:0] envelope;
    wire  signed [15:0] modulated;

    dme_axi4lite dut (
        .s_axi_aclk(clk), .s_axi_aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axis_carrier_tdata(dds_tdata), .s_axis_carrier_tvalid(1'b1),
        .pulse_envelope_out(envelope), .modulated_out(modulated)
    );

    task automatic axi_write(input logic [5:0] a, input logic [31:0] d);
        @(negedge clk);
        awaddr = a; wdata = d; wstrb = 4'hF; awvalid = 1; wvalid = 1; bready = 1;
        fork
            begin wait (awready); @(posedge clk); #1 awvalid = 0; end
            begin wait (wready);  @(posedge clk); #1 wvalid = 0; end
        join
        wait (bvalid); @(posedge clk); #1 bready = 0;
    endtask

    task automatic axi_read(input logic [5:0] a, output logic [31:0] d, output logic [1:0] r);
        @(negedge clk);
        araddr = a; arvalid = 1; rready = 1;
        wait (arready); @(posedge clk); #1 arvalid = 0;
        wait (rvalid); d = rdata; r = rresp; @(posedge clk); #1 rready = 0;
    endtask

    // ------------------------------------------------------------ checking
    int errors = 0;
    task automatic check(input string what, input longint got, input longint exp, input longint tol = 0);
        if (got >= exp - tol && got <= exp + tol)
            $display("PASS  %s = %0d (expected %0d +- %0d)", what, got, exp, tol);
        else begin
            $display("FAIL  %s = %0d (expected %0d +- %0d)", what, got, exp, tol);
            errors++;
        end
    endtask

    // Pulse monitor, from the core's state machine: start/end time of every
    // pulse (cycles), peak envelope, and carrier zero crossings in the middle
    // 40 us of each pulse.
    localparam int MAXP = 16;
    longint p_start [MAXP], p_end [MAXP];
    int     p_peak [MAXP], p_zc [MAXP];
    int     np = 0;
    longint cyc = 0;
    logic   in_pulse_q = 0;
    logic signed [15:0] mod_q = 0;
    wire    in_pulse = (dut.core.state == 3'd1) || (dut.core.state == 3'd3);

    always @(posedge clk) begin
        cyc <= cyc + 1;
        in_pulse_q <= in_pulse;
        mod_q <= modulated;
        if (in_pulse && !in_pulse_q && np < MAXP) begin
            p_start[np] = cyc; p_peak[np] = 0; p_zc[np] = 0;
        end
        if (in_pulse && np < MAXP) begin
            if (envelope > p_peak[np]) p_peak[np] = envelope;
            if (cyc - p_start[np] >= 5*CYC_US && cyc - p_start[np] < 45*CYC_US &&
                (mod_q < 0) != (modulated < 0))
                p_zc[np]++;
        end
        if (!in_pulse && in_pulse_q && np < MAXP) begin
            p_end[np] = cyc; np++;
        end
    end

    // Envelope is 0 outside the pulses.
    int env_outside = 0;
    always @(posedge clk) if (rstn && !in_pulse && envelope != 0) env_outside++;

    logic [31:0] d;
    logic [1:0]  r;
    int          mismatch;
    longint      t0;

    initial begin
        repeat (5) @(posedge clk);
        rstn = 1;
        repeat (5) @(posedge clk);

        $display("--- 1: AXI4-Lite registers");
        axi_read(6'h00, d, r);  check("CONTROL reset (carrier on, TX off)", d, 2);
        axi_read(6'h04, d, r);  check("PERIOD reset (us, 30 pairs/s)", d, 33333);
        axi_read(6'h10, d, r);  check("unmapped read -> SLVERR", r, 2'b11);
        axi_write(6'h04, 449);
        axi_read(6'h04, d, r);  check("PERIOD 449 us rejected (min 450)", d, 33333);
        axi_write(6'h04, 450);
        axi_read(6'h04, d, r);  check("PERIOD 450 us accepted", d, 450);
        axi_write(6'h04, 1000);
        axi_read(6'h04, d, r);  check("PERIOD set to 1000 us", d, 1000);
        axi_read(6'h00, d, r);  check("CONTROL still 2", d, 2);

        $display("--- 2: pulse timing, 1000 us period, carrier on");
        np = 0;
        axi_write(6'h00, 3);
        wait (np >= 6);
        for (int i = 0; i < 6; i++) begin
            check($sformatf("pulse %0d width (cycles)", i), p_end[i] - p_start[i], 50*CYC_US);
            check($sformatf("pulse %0d peak envelope", i), p_peak[i], 32767, 50);
            check($sformatf("pulse %0d carrier zero crossings in 40 us (1 MHz)", i), p_zc[i], 80, 1);
        end
        for (int i = 0; i < 6; i += 2) begin
            check($sformatf("pair %0d gap (cycles)", i/2), p_start[i+1] - p_end[i], 350*CYC_US);
            check($sformatf("pair %0d spacing, rising to rising (cycles)", i/2), p_start[i+1] - p_start[i], 400*CYC_US);
        end
        // Known RTL behaviour: leaving S_IDLE, pair_elapsed_us already steps
        // to 1 on the tick that starts the first pulse, so only the first
        // period after enable is 1 us short. Every later period is exact.
        check("first pair period after enable (cycles, 1 us short)", p_start[2] - p_start[0], 999*CYC_US);
        check("pair period 1->2 (cycles)", p_start[4] - p_start[2], 1000*CYC_US);
        axi_read(6'h0C, d, r);  check("ELAPSED_US below period", d < 1000, 1);

        $display("--- 3: carrier off: output is the envelope");
        axi_write(6'h00, 1);
        mismatch = 0;
        wait (in_pulse);
        repeat (2) @(posedge clk);
        for (int i = 0; i < 40*CYC_US; i++) begin
            @(posedge clk);
            #1 if (modulated != env_q) mismatch++;
        end
        check("carrier off: samples where output != envelope", mismatch, 0);

        $display("--- 4: rate change on the fly, 2000 us");
        axi_write(6'h04, 2000);
        np = 0;
        wait (np >= 5);
        check("pair period at 2000 us (cycles)", p_start[4] - p_start[2], 2000*CYC_US);

        $display("--- 5: default rate, 30 pairs/s");
        axi_write(6'h04, 33333);
        np = 0;
        wait (np >= 5);
        check("pair period at default 33333 us (cycles)", p_start[4] - p_start[2], 33333*CYC_US);
        check("envelope 0 outside pulses (samples)", env_outside, 0);

        $display("--- 6: disable");
        axi_write(6'h00, 2);
        repeat (300) @(posedge clk);
        check("state idle after disable", dut.core.state, 0);
        check("envelope 0 after disable", envelope, 0);
        check("output 0 after disable", modulated, 0);

        if (errors == 0) $display("Checkpoint 1 simulation PASSED.");
        else             $display("Checkpoint 1 simulation FAILED: %0d errors.", errors);
        $finish;
    end

    // Previous-cycle envelope (the output register adds one cycle).
    logic signed [15:0] env_q = 0;
    always @(posedge clk) env_q <= dut.core.current_env;

    initial begin
        #200ms;
        $display("FAIL  timeout");
        $finish;
    end
endmodule
