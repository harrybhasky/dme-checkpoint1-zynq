`timescale 1ns/1ps

// Self-checking testbench for checkpoint 3.
//
//   aircraft TX (checkpoint 1, 1 MHz) ─► ground station ─► aircraft RX (checkpoint 2)
//                                        (1.25 MHz reply)
//
// The testbench times the half-amplitude points of the interrogation's second
// pulse and the reply's first pulse itself, so the ground station delay is
// checked independently of its own registers. The aircraft side measures the
// same delay through the receiver's TX correlation and converts it to range.
module tb_dme_gs;
    localparam int unsigned CLK_HZ        = 100_000_000;
    localparam int unsigned CLOCKS_PER_US = CLK_HZ / 1_000_000;
    localparam int unsigned HALF_LEVEL    = 16384;
    localparam int unsigned REPLY_DELAY   = 50 * CLOCKS_PER_US;
    localparam int unsigned PAIR_SPACING  = 400 * CLOCKS_PER_US;
    // Threshold-crossing jitter from the carrier phase at the pulse start
    // (2 MHz ripple after rectification): 0.3 us, 0.024 NM.
    localparam int          JITTER        = 30;
    localparam real         PI            = 3.14159265358979;

    // Ground station registers
    localparam logic [6:0] GS_CONTROL       = 7'h00;
    localparam logic [6:0] GS_STATUS        = 7'h04;
    localparam logic [6:0] GS_RANGE         = 7'h34;
    localparam logic [6:0] GS_VELOCITY      = 7'h38;
    localparam logic [6:0] GS_RANGE_MIN     = 7'h3C;
    localparam logic [6:0] GS_EFFICIENCY    = 7'h44;
    localparam logic [6:0] GS_INTERROGATIONS = 7'h48;
    localparam logic [6:0] GS_REPLIES       = 7'h4C;
    localparam logic [6:0] GS_SKIPPED       = 7'h50;
    localparam logic [6:0] GS_DROPPED       = 7'h54;
    localparam logic [6:0] GS_REJECTED      = 7'h58;

    // Aircraft receiver registers
    localparam logic [6:0] RX_CONTROL       = 7'h00;
    localparam logic [6:0] RX_STATUS        = 7'h04;
    localparam logic [6:0] RX_PAIR_FIFO     = 7'h2C;
    localparam logic [6:0] RX_PAIR_DELAY    = 7'h48;

    localparam bit GS = 1'b0;
    localparam bit RX = 1'b1;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    int errors = 0;

    function automatic int nm_to_cycles(input int nm);
        return int'((64'(nm) * 64'd3704 * 64'(CLK_HZ) + 64'd149_896_229) /
                    64'd299_792_458);
    endfunction

    // ------------------------------------------------------------------
    // Aircraft transmitter (checkpoint 1) on a 1 MHz DDS model
    // ------------------------------------------------------------------
    logic               tx_enable = 1'b0;
    logic [31:0]        tx_period_us = 32'd1000;
    logic signed [15:0] tx_carrier;
    logic signed [15:0] gs_carrier;
    logic [15:0]        tx_envelope;
    logic signed [15:0] tx_modulated;

    always @(posedge clk) begin
        tx_carrier <= $rtoi(16383.0 * $sin(2.0 * PI * $realtime / 1000.0));
        gs_carrier <= $rtoi(16383.0 * $sin(2.0 * PI * $realtime / 800.0));
    end

    dme_pulse_pair_modulator #(.CLK_HZ(CLK_HZ)) tx (
        .clk(clk),
        .rst_n(rst_n),
        .enable(tx_enable),
        .carrier_enable(1'b1),
        .pair_period_us(tx_period_us),
        .s_axis_carrier_tdata(tx_carrier),
        .s_axis_carrier_tvalid(1'b1),
        .elapsed_us(),
        .pulse_envelope_out(tx_envelope),
        .modulated_out(tx_modulated)
    );

    // ------------------------------------------------------------------
    // Shared AXI4-Lite master, steered to the GS or the RX by sel
    // ------------------------------------------------------------------
    bit          sel = GS;
    logic [6:0]  awaddr = '0, araddr = '0;
    logic        awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [31:0] wdata = '0;
    logic        gs_awready, gs_wready, gs_bvalid, gs_arready, gs_rvalid;
    logic        rx_awready, rx_wready, rx_bvalid, rx_arready, rx_rvalid;
    logic [1:0]  gs_bresp, gs_rresp, rx_bresp, rx_rresp;
    logic [31:0] gs_rdata, rx_rdata;

    wire        awready = sel ? rx_awready : gs_awready;
    wire        wready  = sel ? rx_wready  : gs_wready;
    wire        bvalid  = sel ? rx_bvalid  : gs_bvalid;
    wire        arready = sel ? rx_arready : gs_arready;
    wire        rvalid  = sel ? rx_rvalid  : gs_rvalid;
    wire [31:0] rdata   = sel ? rx_rdata   : gs_rdata;

    // ------------------------------------------------------------------
    // Ground station under test
    // ------------------------------------------------------------------
    logic signed [15:0] reply_out;
    logic [15:0]        reply_envelope;
    logic               reply_active;

    dme_gs_axi4lite #(.CLK_HZ(CLK_HZ)) gs (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid && sel == GS),
        .s_axi_awready(gs_awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(4'hF),
        .s_axi_wvalid(wvalid && sel == GS),
        .s_axi_wready(gs_wready),
        .s_axi_bresp(gs_bresp),
        .s_axi_bvalid(gs_bvalid),
        .s_axi_bready(bready && sel == GS),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid && sel == GS),
        .s_axi_arready(gs_arready),
        .s_axi_rdata(gs_rdata),
        .s_axi_rresp(gs_rresp),
        .s_axi_rvalid(gs_rvalid),
        .s_axi_rready(rready && sel == GS),
        .loopback_sample(tx_modulated),
        .adc_sample(16'sd0),
        .adc_sample_valid(1'b0),
        .s_axis_carrier_tdata(gs_carrier),
        .s_axis_carrier_tvalid(1'b1),
        .reply_out(reply_out),
        .reply_envelope_out(reply_envelope),
        .envelope_out(),
        .interrogation_detected(),
        .reply_active(reply_active)
    );

    // ------------------------------------------------------------------
    // Aircraft receiver (checkpoint 2 with TX correlation)
    // ------------------------------------------------------------------
    dme_rx_axi4lite #(.CLK_HZ(CLK_HZ)) rx (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid && sel == RX),
        .s_axi_awready(rx_awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(4'hF),
        .s_axi_wvalid(wvalid && sel == RX),
        .s_axi_wready(rx_wready),
        .s_axi_bresp(rx_bresp),
        .s_axi_bvalid(rx_bvalid),
        .s_axi_bready(bready && sel == RX),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid && sel == RX),
        .s_axi_arready(rx_arready),
        .s_axi_rdata(rx_rdata),
        .s_axi_rresp(rx_rresp),
        .s_axi_rvalid(rx_rvalid),
        .s_axi_rready(rready && sel == RX),
        .loopback_sample(reply_out),
        .adc_sample(16'sd0),
        .adc_sample_valid(1'b0),
        .tx_envelope(tx_envelope),
        .envelope_out(),
        .pulse_detected(),
        .pair_detected(),
        .irq()
    );

    // ------------------------------------------------------------------
    // Independent timing monitor (half-amplitude crossings)
    // ------------------------------------------------------------------
    longint cycle = 0;
    always @(posedge clk) cycle <= cycle + 1;

    longint tx_second_pulse [$];
    int     gs_delays [$];
    bit     tx_above = 0, tx_odd = 0, reply_above = 0, reply_odd = 0;

    always @(posedge clk) begin
        tx_above    <= tx_envelope >= HALF_LEVEL;
        reply_above <= reply_envelope >= HALF_LEVEL;
        if (!tx_enable) begin
            tx_odd <= 0;
        end else if (tx_envelope >= HALF_LEVEL && !tx_above) begin
            if (tx_odd)
                tx_second_pulse.push_back(cycle);
            tx_odd <= !tx_odd;
        end
        if (reply_envelope >= HALF_LEVEL && !reply_above) begin
            if (!reply_odd && tx_second_pulse.size() > 0)
                gs_delays.push_back(int'(cycle - tx_second_pulse.pop_front()));
            reply_odd <= !reply_odd;
        end
    end

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    task automatic axi_write(input bit target, input logic [6:0] addr,
                             input logic [31:0] data);
        @(posedge clk) #1;
        sel = target;
        awaddr = addr; awvalid = 1; wdata = data; wvalid = 1; bready = 1;
        while (awvalid || wvalid) begin
            @(posedge clk);
            if (awready) awvalid <= 0;
            if (wready)  wvalid  <= 0;
            #1;
        end
        while (!bvalid) @(posedge clk);
        @(posedge clk) #1 bready = 0;
    endtask

    task automatic axi_read(input bit target, input logic [6:0] addr,
                            output logic [31:0] data);
        @(posedge clk) #1;
        sel = target;
        araddr = addr; arvalid = 1; rready = 1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        #1 arvalid = 0;
        while (!rvalid) @(posedge clk);
        data = rdata;
        @(posedge clk) #1 rready = 0;
    endtask

    task automatic expect_eq(input string what, input logic [31:0] got,
                             input logic [31:0] expected);
        if (got !== expected) begin
            $display("FAIL  %s: got %0d, expected %0d", what, got, expected);
            errors++;
        end else begin
            $display("PASS  %s = %0d", what, got);
        end
    endtask

    task automatic expect_near(input string what, input int got,
                               input int expected, input int tol);
        int diff = got - expected;
        if (diff > tol || diff < -tol) begin
            $display("FAIL  %s: got %0d, expected %0d +- %0d", what, got, expected, tol);
            errors++;
        end else begin
            $display("PASS  %s = %0d (expected %0d +- %0d)", what, got, expected, tol);
        end
    endtask

    task automatic wait_us(input int us);
        repeat (us * CLOCKS_PER_US) @(posedge clk);
    endtask

    // Sends exactly n interrogation pairs, then waits settle_us for replies.
    task automatic interrogate(input int period_us, input int n, input int settle_us);
        tx_period_us = period_us;
        tx_enable = 1'b1;
        wait_us(1 + (n - 1) * period_us + 460);
        tx_enable = 1'b0;
        wait_us(settle_us);
    endtask

    task automatic clear_all(input logic [31:0] gs_control);
        axi_write(GS, GS_CONTROL, gs_control | 32'h8000_0000);
        axi_write(RX, RX_CONTROL, 32'h8000_0001);
        gs_delays.delete();
        tx_second_pulse.delete();
    endtask

    // Checks every reply the monitor timed in this section.
    task automatic check_gs_delays(input string what, input int n, input int range_cycles);
        expect_eq({what, " replies timed"}, gs_delays.size(), n);
        foreach (gs_delays[i])
            expect_near($sformatf("%s reply %0d delay (cycles)", what, i),
                        gs_delays[i], REPLY_DELAY + range_cycles, JITTER);
    endtask

    // Pops one aircraft-side pair, returning its TX-to-RX delay.
    task automatic rx_pop(output logic [31:0] delay, output bit valid);
        logic [31:0] status, ts;
        axi_read(RX, RX_STATUS, status);
        valid = !status[1];
        delay = 32'd0;
        if (valid) begin
            axi_read(RX, RX_PAIR_DELAY, delay);
            axi_read(RX, RX_PAIR_FIFO, ts);
        end
    endtask

    logic [31:0] value, delay, range_a, range_b;
    bit          valid;
    int          zero_delay, range_cycles, prev, replies, d;
    real         nm;

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        axi_read(GS, GS_RANGE, value);
        expect_eq("Default range (10 NM, cycles)", value, nm_to_cycles(10));
        axi_write(RX, RX_CONTROL, 32'h1);

        // ---------------- 1: zero-range calibration ----------------
        $display("--- 1: zero range, aircraft receiver calibration");
        axi_write(GS, GS_RANGE, 0);
        axi_write(GS, GS_CONTROL, 32'h1);
        interrogate(1000, 3, 600);
        check_gs_delays("1", 3, 0);
        axi_read(GS, GS_INTERROGATIONS, value); expect_eq("1 interrogations", value, 3);
        axi_read(GS, GS_REPLIES, value);        expect_eq("1 replies", value, 3);
        axi_read(GS, GS_REJECTED, value);       expect_eq("1 rejected pulses", value, 0);
        zero_delay = 0;
        for (int i = 0; i < 3; i++) begin
            rx_pop(delay, valid);
            expect_near($sformatf("1 aircraft pair %0d delay over 450 us (cycles)", i),
                        int'(delay) - PAIR_SPACING - REPLY_DELAY, 67, JITTER);
            zero_delay += delay;
        end
        zero_delay /= 3;
        $display("INFO  zero-range calibration: TX-to-RX delay = %0d cycles", zero_delay);

        // ---------------- 2: distance model ----------------
        for (int k = 0; k < 3; k++) begin
            d = (k == 0) ? 10 : (k == 1) ? 100 : 200;
            $display("--- 2: range %0d NM", d);
            range_cycles = nm_to_cycles(d);
            clear_all(32'h1);
            axi_write(GS, GS_RANGE, range_cycles);
            interrogate(3000, 2, 3000);
            check_gs_delays($sformatf("2 %0d NM", d), 2, range_cycles);
            for (int i = 0; i < 2; i++) begin
                rx_pop(delay, valid);
                nm = real'(int'(delay) - zero_delay) / (real'(CLOCKS_PER_US) * 12.355214);
                expect_near($sformatf("2 %0d NM aircraft round trip (cycles)", d),
                            int'(delay) - zero_delay, range_cycles, JITTER);
                $display("INFO  aircraft measures %0.3f NM", nm);
            end
        end

        // ---------------- 3: several replies outstanding ----------------
        $display("--- 3: 200 NM at a 600 us interrogation period");
        range_cycles = nm_to_cycles(200);
        clear_all(32'h1);
        axi_write(GS, GS_RANGE, range_cycles);
        interrogate(600, 8, 3000);
        axi_read(GS, GS_REPLIES, value); expect_eq("3 replies", value, 8);
        axi_read(GS, GS_DROPPED, value); expect_eq("3 dropped", value, 0);
        check_gs_delays("3", 8, range_cycles);

        // ---------------- 4: aircraft motion ----------------
        $display("--- 4: aircraft flying towards the station");
        range_cycles = nm_to_cycles(50);
        clear_all(32'h5);                                // enable, motion
        axi_write(GS, GS_VELOCITY, -(200 << 16));       // -200 cycles per ms
        axi_write(GS, GS_RANGE, range_cycles);
        axi_read(GS, GS_RANGE, range_a);
        wait_us(5000);
        axi_read(GS, GS_RANGE, range_b);
        expect_eq("4 range change over 5 ms (cycles)", range_a - range_b, 1000);
        // 2 ms period: the round trip plus 450 us must fit inside the period.
        interrogate(2000, 4, 1500);
        expect_eq("4 replies timed", gs_delays.size(), 4);
        for (int i = 1; i < gs_delays.size(); i++)
            expect_near($sformatf("4 delay change, reply %0d (cycles)", i),
                        gs_delays[i] - gs_delays[i-1], -400, 3);
        rx_pop(delay, valid);
        for (int i = 1; i < 4; i++) begin
            prev = delay;
            rx_pop(delay, valid);
            expect_near($sformatf("4 aircraft delay change, pair %0d (cycles)", i),
                        int'(delay) - prev, -400, 2 * JITTER);
        end

        axi_read(GS, GS_RANGE_MIN, value);
        axi_write(GS, GS_RANGE, value + 50);
        wait_us(4000);
        axi_read(GS, GS_RANGE, range_b); expect_eq("4 range clamped at minimum", range_b, value);
        axi_read(GS, GS_STATUS, value);  expect_eq("4 at-limit status", value[3], 1);

        // ---------------- 5: reply efficiency ----------------
        $display("--- 5: reply efficiency");
        clear_all(32'h1);
        axi_write(GS, GS_VELOCITY, 0);
        axi_write(GS, GS_RANGE, 0);
        axi_write(GS, GS_EFFICIENCY, 0);
        interrogate(1000, 3, 200);
        axi_read(GS, GS_REPLIES, value);  expect_eq("5 0% replies", value, 0);
        axi_read(GS, GS_SKIPPED, value);  expect_eq("5 0% skipped", value, 3);

        clear_all(32'h1);
        axi_write(GS, GS_EFFICIENCY, 50);
        interrogate(460, 20, 200);
        axi_read(GS, GS_INTERROGATIONS, value); expect_eq("5 50% interrogations", value, 20);
        axi_read(GS, GS_REPLIES, value);
        replies = value;
        axi_read(GS, GS_SKIPPED, value);
        expect_eq("5 50% replies + skipped", replies + value, 20);
        expect_near("5 50% replies", replies, 10, 5);
        axi_read(GS, GS_DROPPED, value);  expect_eq("5 50% dropped", value, 0);

        if (errors == 0)
            $display("Checkpoint 3 simulation PASSED.");
        else
            $display("Checkpoint 3 simulation FAILED with %0d error(s).", errors);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("FAIL  timeout");
        $finish;
    end
endmodule
