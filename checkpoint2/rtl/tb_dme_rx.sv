`timescale 1ns/1ps

// Self-checking testbench for checkpoint 2.
//
// Part A: digital loopback. The checkpoint 1 modulator (raised-cosine pulse
//         pairs on a 1 MHz DDS sine) feeds the receiver directly.
// Part B: ADC path. A behavioural ADC (10 MSPS, DC offset, noise) plays
//         valid pairs, a lone pulse, wrong spacing, wrong width and a pair
//         with an interfering pulse between its two pulses.
module tb_dme_rx;
    localparam int unsigned CLK_HZ        = 100_000_000;
    localparam int unsigned CLOCKS_PER_US = CLK_HZ / 1_000_000;
    localparam int unsigned TX_PERIOD_US  = 1000;
    localparam real         PI            = 3.14159265358979;

    localparam logic [6:0] REG_CONTROL      = 7'h00;
    localparam logic [6:0] REG_STATUS       = 7'h04;
    localparam logic [6:0] REG_DC_OFFSET    = 7'h08;
    localparam logic [6:0] REG_ENV_SHIFT    = 7'h0C;
    localparam logic [6:0] REG_THRESH_HIGH  = 7'h10;
    localparam logic [6:0] REG_THRESH_LOW   = 7'h14;
    localparam logic [6:0] REG_PAIR_FIFO    = 7'h2C;
    localparam logic [6:0] REG_PAIR_COUNT   = 7'h30;
    localparam logic [6:0] REG_PULSE_COUNT  = 7'h34;
    localparam logic [6:0] REG_REJECT_COUNT = 7'h38;
    localparam logic [6:0] REG_LAST_WIDTH   = 7'h3C;
    localparam logic [6:0] REG_LAST_SPACING = 7'h40;
    localparam logic [6:0] REG_PAIR_DELAY   = 7'h48;
    localparam logic [6:0] REG_TX_COUNT     = 7'h4C;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    int errors = 0;

    // ------------------------------------------------------------------
    // Transmitter: checkpoint 1 modulator with a 1 MHz, 15-bit DDS model
    // ------------------------------------------------------------------
    logic               tx_enable = 1'b0;
    logic signed [15:0] dds_sine;
    logic [15:0]        tx_envelope;
    logic signed [15:0] tx_modulated;

    always @(posedge clk)
        dds_sine <= $rtoi(16383.0 * $sin(2.0 * PI * $realtime / 1000.0));

    dme_pulse_pair_modulator #(.CLK_HZ(CLK_HZ)) tx (
        .clk(clk),
        .rst_n(rst_n),
        .enable(tx_enable),
        .carrier_enable(1'b1),
        .pair_period_us(TX_PERIOD_US),
        .s_axis_carrier_tdata(dds_sine),
        .s_axis_carrier_tvalid(1'b1),
        .elapsed_us(),
        .pulse_envelope_out(tx_envelope),
        .modulated_out(tx_modulated)
    );

    // ------------------------------------------------------------------
    // Behavioural ADC: 10 MSPS, offset 3000, amplitude 12000, noise +-1500
    // ------------------------------------------------------------------
    localparam int  ADC_DIV       = 10;
    localparam int  ADC_OFFSET    = 3000;
    localparam real ADC_AMPLITUDE = 12000.0;
    localparam int  ADC_NOISE     = 1500;

    real                adc_env = 0.0;
    int                 adc_div = 0;
    int                 noise_seed = 42;
    logic signed [15:0] adc_sample = '0;
    logic               adc_sample_valid = 1'b0;

    always @(posedge clk) begin
        adc_div          <= (adc_div == ADC_DIV - 1) ? 0 : adc_div + 1;
        adc_sample_valid <= (adc_div == ADC_DIV - 1);
        if (adc_div == ADC_DIV - 1)
            adc_sample <= ADC_OFFSET +
                          $rtoi(adc_env * ADC_AMPLITUDE *
                                $sin(2.0 * PI * $realtime / 1000.0)) +
                          ($random(noise_seed) % (ADC_NOISE + 1));
    end

    // Raised-cosine pulse (same shape as the transmitter) or rectangular.
    task automatic adc_pulse(input bit raised_cosine, input int width_us);
        int n = width_us * CLOCKS_PER_US;
        for (int i = 0; i < n; i++) begin
            @(posedge clk);
            adc_env = raised_cosine ? 0.5 * (1.0 - $cos(2.0 * PI * i / n)) : 1.0;
        end
        adc_env = 0.0;
    endtask

    task automatic adc_idle(input int us);
        repeat (us * CLOCKS_PER_US) @(posedge clk);
    endtask

    // ------------------------------------------------------------------
    // Receiver under test
    // ------------------------------------------------------------------
    logic [6:0]  awaddr = '0, araddr = '0;
    logic        awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [31:0] wdata = '0;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;
    logic [31:0] rdata;
    logic [15:0] envelope;
    logic        pulse_detected, pair_detected, irq;

    dme_rx_axi4lite #(.CLK_HZ(CLK_HZ)) dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(4'hF),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .loopback_sample(tx_modulated),
        .adc_sample(adc_sample),
        .adc_sample_valid(adc_sample_valid),
        .tx_envelope(tx_envelope),
        .envelope_out(envelope),
        .pulse_detected(pulse_detected),
        .pair_detected(pair_detected),
        .irq(irq)
    );

    task automatic axi_write(input logic [6:0] addr, input logic [31:0] data);
        @(posedge clk) #1;
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

    task automatic axi_read(input logic [6:0] addr, output logic [31:0] data);
        @(posedge clk) #1;
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

    task automatic expect_near(input string what, input logic [31:0] got,
                               input logic [31:0] expected, input int tol);
        int diff = int'(got) - int'(expected);
        if (diff > tol || diff < -tol) begin
            $display("FAIL  %s: got %0d, expected %0d +- %0d", what, got, expected, tol);
            errors++;
        end else begin
            $display("PASS  %s = %0d (expected %0d +- %0d)", what, got, expected, tol);
        end
    endtask

    task automatic clear_rx(input logic [31:0] control);
        axi_write(REG_CONTROL, control | 32'h8000_0000);
    endtask

    logic [31:0] value, prev_ts, count;

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // ---------------- Part A: digital loopback ----------------
        $display("--- Part A: checkpoint 1 TX -> RX digital loopback");
        axi_write(REG_CONTROL, 32'h1);          // enable, loopback input
        tx_enable = 1'b1;
        repeat (5 * TX_PERIOD_US * CLOCKS_PER_US + 500 * CLOCKS_PER_US) @(posedge clk);

        axi_read(REG_PAIR_COUNT, value);   expect_eq("A pair count", value, 6);
        axi_read(REG_REJECT_COUNT, value); expect_eq("A rejected pulses", value, 0);
        axi_read(REG_PULSE_COUNT, value);  expect_eq("A valid pulses", value, 12);
        axi_read(REG_LAST_SPACING, value);
        expect_near("A pulse spacing (cycles)", value, 400 * CLOCKS_PER_US, 2);
        axi_read(REG_LAST_WIDTH, value);
        $display("INFO  A measured pulse width = %0d cycles (%0.2f us)",
                 value, real'(value) / CLOCKS_PER_US);
        axi_read(REG_TX_COUNT, value);     expect_eq("A TX pairs tapped", value, 6);
        // Loopback has no range delay: what remains is the receiver's
        // latency from the TX half-amplitude point to the detected edge.
        axi_read(REG_PAIR_DELAY, value);
        expect_near("A TX-to-RX delay (cycles)", value, 67, 10);
        if (!irq) begin
            $display("INFO  irq low as expected (irq disabled)");
        end

        // The first period after TX enable is 1 us short: the checkpoint 1
        // FSM spends one tick in S_IDLE. Check the steady-state periods.
        axi_read(REG_PAIR_FIFO, prev_ts);
        axi_read(REG_PAIR_FIFO, prev_ts);
        for (int i = 2; i < 6; i++) begin
            axi_read(REG_PAIR_FIFO, value);
            expect_near($sformatf("A pair %0d -> %0d period (cycles)", i - 1, i),
                        value - prev_ts, TX_PERIOD_US * CLOCKS_PER_US, 2);
            prev_ts = value;
        end
        axi_read(REG_STATUS, value);
        expect_eq("A FIFO empty after draining", value[1], 1);

        tx_enable = 1'b0;

        // ---------------- Part B: ADC path ----------------
        $display("--- Part B: noisy ADC input with DC offset");
        axi_write(REG_DC_OFFSET, ADC_OFFSET);
        axi_write(REG_ENV_SHIFT, 4);            // tau = 16 samples = 1.6 us
        axi_write(REG_THRESH_HIGH, 3800);       // ~50% of mean |A sin|
        axi_write(REG_THRESH_LOW, 3000);
        clear_rx(32'h7);                        // enable, ADC input, irq enable
        adc_idle(100);

        adc_pulse(1, 50); adc_idle(350); adc_pulse(1, 50); adc_idle(1000);
        axi_read(REG_PAIR_COUNT, value);   expect_eq("B1 valid pair", value, 1);
        expect_eq("B1 irq asserted", irq, 1);

        adc_pulse(1, 50); adc_idle(1500);
        axi_read(REG_PAIR_COUNT, value);   expect_eq("B2 lone pulse adds no pair", value, 1);

        adc_pulse(1, 50); adc_idle(250); adc_pulse(1, 50); adc_idle(1000);
        axi_read(REG_PAIR_COUNT, value);   expect_eq("B3 300 us spacing adds no pair", value, 1);

        adc_pulse(0, 80); adc_idle(320); adc_pulse(0, 80); adc_idle(1000);
        axi_read(REG_PAIR_COUNT, value);   expect_eq("B4 wide pulses add no pair", value, 1);
        axi_read(REG_REJECT_COUNT, value); expect_eq("B4 wide pulses rejected", value, 2);

        adc_pulse(1, 50); adc_idle(150); adc_pulse(1, 50);
        adc_idle(150); adc_pulse(1, 50); adc_idle(1000);
        axi_read(REG_PAIR_COUNT, value);   expect_eq("B5 pair with interferer", value, 2);
        axi_read(REG_LAST_SPACING, value);
        expect_near("B5 pair spacing (cycles)", value, 400 * CLOCKS_PER_US, 50);

        axi_read(REG_PULSE_COUNT, value);  expect_eq("B valid pulses", value, 8);
        axi_read(REG_STATUS, value);       count = value[12:8];
        expect_eq("B FIFO holds both pairs", count, 2);

        if (errors == 0)
            $display("Checkpoint 2 simulation PASSED.");
        else
            $display("Checkpoint 2 simulation FAILED with %0d error(s).", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("FAIL  timeout");
        $finish;
    end
endmodule
