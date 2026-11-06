`timescale 1ns/1ps

// Self-checking testbench for checkpoint 4 (final project, basic
// requirement 1).
//
//   dme_aircraft_axi4lite ──tx_sample──► groundStation (course IP) ──o_gs_out──► dme_aircraft_axi4lite
//                                              ▲
//   dme_gs_ctrl_axi4lite ──distance, efficiency, ... ─┘
//
// The ground station is the unmodified course IP, with behavioural models of
// its Xilinx cores (sim/models). The testbench checks:
//
//   1. Format: the station accepts every interrogation. Its demodulator
//      sees 6.5 to 7.5 us pulses with a 4.5 to 5.5 us gap, and it raises no
//      pulse width or delay error. The aircraft decodes every reply.
//   2. Zero range: the interrogation-to-reply delay (calibration constant).
//   3. Static distances from 1 km to 389 km: the delay grows by twice the
//      station's one-way delay, and the distance software would compute is
//      within 12 m (7 cycles of carrier-phase spread plus the station's own
//      rounding) of the distance set in the station.
//   4. 60% reply efficiency: about 60% of interrogations are answered and
//      every answer still gives the right distance.
//   5. Squitter at 2500 pps, static at 10 km (requirement 4): squitter pairs
//      reach the aircraft, the range gate drops the ones beyond MAX_DELAY,
//      the FIFO never overflows.
//   6. Moving towards the station, 60% efficiency, squitter at 2500 pps
//      (requirement 6). The station's distance model is sped up 100x by
//      forcing its countPerKM (1 km every 10 ms instead of every 5 s).
//
// Tests 5 and 6 write the aircraft's reply FIFO (time, delay) to
// squitter_static.txt and squitter_moving.txt. run_sim.sh then runs the
// board software's tracker (software/dme_track.c) on them and checks the
// distance and speed it reports.
module tb_dme_ckpt4;
    localparam int unsigned CLK_HZ = 100_000_000;

    // Aircraft registers
    localparam logic [6:0] AC_CONTROL      = 7'h00;
    localparam logic [6:0] AC_STATUS       = 7'h04;
    localparam logic [6:0] AC_TX_PERIOD    = 7'h08;
    localparam logic [6:0] AC_TX_JITTER    = 7'h0C;
    localparam logic [6:0] AC_TX_COUNT     = 7'h34;
    localparam logic [6:0] AC_REPLY_DELAY  = 7'h38;
    localparam logic [6:0] AC_REPLY_TIME   = 7'h3C;
    localparam logic [6:0] AC_REPLY_COUNT  = 7'h40;
    localparam logic [6:0] AC_REJECT_COUNT = 7'h48;
    localparam logic [6:0] AC_LAST_WIDTH   = 7'h4C;
    localparam logic [6:0] AC_LAST_SPACING = 7'h50;
    localparam logic [6:0] AC_MAX_DELAY    = 7'h54;
    localparam logic [6:0] AC_GATED_COUNT  = 7'h58;

    // Ground station control registers
    localparam logic [6:0] GC_CONTROL      = 7'h00;
    localparam logic [6:0] GC_DISTANCE     = 7'h04;
    localparam logic [6:0] GC_SPEED        = 7'h08;
    localparam logic [6:0] GC_EFFICIENCY   = 7'h0C;
    localparam logic [6:0] GC_PULSE_RATE   = 7'h10;
    localparam logic [6:0] GC_DISTANCE_NOW = 7'h14;
    localparam logic [6:0] GC_PW_ERRORS    = 7'h1C;
    localparam logic [6:0] GC_PD_ERRORS    = 7'h20;

    localparam logic [31:0] GC_MOTION   = 32'h01;
    localparam logic [31:0] GC_SQUITTER = 32'h04;
    localparam logic [31:0] GC_PULSE_EN = 32'h20;
    localparam logic [31:0] AC_STATUS_OVERFLOW = 32'h8;

    // The station's one-way delay is floor(d * 334 * 33 / 32768) cycles
    // (delayModel.v), 3.364 us per km.
    localparam real METERS_PER_CYCLE = 32768.0 / (334.0 * 33.0);
    // At zero range the station's delay FIFO starts reading 2 cycles earlier
    // than at any other distance, so software calibrates at a non-zero one.
    localparam int  ZERO_RANGE_BIAS = 2;
    // Spread of the reply delay from the 10 MHz carrier phase at the start
    // of each pulse: the station's peak detector and our IIR both follow the
    // rectified carrier peaks. 7 cycles round trip is 5 m.
    localparam int  DELAY_TOL = 7;

    localparam bit AC = 1'b0;
    localparam bit GC = 1'b1;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    int errors = 0;

    // ------------------------------------------------------------------
    // AXI4-Lite master shared by both peripherals
    // ------------------------------------------------------------------
    bit          sel;
    logic [6:0]  awaddr, araddr;
    logic        awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [31:0] wdata;
    logic        ac_awready, ac_wready, ac_bvalid, ac_arready, ac_rvalid;
    logic        gc_awready, gc_wready, gc_bvalid, gc_arready, gc_rvalid;
    logic [1:0]  ac_bresp, ac_rresp, gc_bresp, gc_rresp;
    logic [31:0] ac_rdata, gc_rdata;

    wire        awready = (sel == AC) ? ac_awready : gc_awready;
    wire        wready  = (sel == AC) ? ac_wready  : gc_wready;
    wire        bvalid  = (sel == AC) ? ac_bvalid  : gc_bvalid;
    wire        arready = (sel == AC) ? ac_arready : gc_arready;
    wire        rvalid  = (sel == AC) ? ac_rvalid  : gc_rvalid;
    wire [31:0] rdata   = (sel == AC) ? ac_rdata   : gc_rdata;

    // ------------------------------------------------------------------
    // Aircraft, ground station control and the course ground station
    // ------------------------------------------------------------------
    logic signed [11:0] tx_sample;
    logic               tx_pulse;
    logic               tx_start;
    logic [15:0]        rx_envelope;
    logic               rx_pulse;
    logic               reply_detected;
    wire  [11:0]        gs_out;
    // ppGen.v reads pulseBRAM one address past its 701 entries at the end of
    // a 701-cycle reply pulse. In simulation that sample is X, and an X would
    // stick in the receiver's IIR filter. The synthesised ROM returns a
    // defined value, so the testbench passes X on as 0.
    wire  [11:0]        gs_out_clean = $isunknown(gs_out) ? 12'd0 : gs_out;

    logic [19:0] gs_distance, gs_distance_now, gs_pulse_rate;
    logic [7:0]  gs_speed;
    logic [6:0]  gs_efficiency;
    logic        gs_direction, gs_var_distance, gs_squitter_en, gs_jitter_en;
    logic        gs_ident, gs_pulse_en, gs_pw_error, gs_pd_error;
    wire         gs_pulse;

    dme_aircraft_axi4lite aircraft (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid && sel == AC),
        .s_axi_awready(ac_awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(4'hF),
        .s_axi_wvalid(wvalid && sel == AC),
        .s_axi_wready(ac_wready),
        .s_axi_bresp(ac_bresp),
        .s_axi_bvalid(ac_bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid && sel == AC),
        .s_axi_arready(ac_arready),
        .s_axi_rdata(ac_rdata),
        .s_axi_rresp(ac_rresp),
        .s_axi_rvalid(ac_rvalid),
        .s_axi_rready(rready),
        .tx_sample(tx_sample),
        .tx_pulse(tx_pulse),
        .rx_sample(gs_out_clean),
        .tx_start(tx_start),
        .rx_envelope(rx_envelope),
        .rx_pulse(rx_pulse),
        .reply_detected(reply_detected),
        .irq()
    );

    dme_gs_ctrl_axi4lite gs_ctrl (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),
        .s_axi_awaddr(awaddr[5:0]),
        .s_axi_awvalid(awvalid && sel == GC),
        .s_axi_awready(gc_awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(4'hF),
        .s_axi_wvalid(wvalid && sel == GC),
        .s_axi_wready(gc_wready),
        .s_axi_bresp(gc_bresp),
        .s_axi_bvalid(gc_bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr[5:0]),
        .s_axi_arvalid(arvalid && sel == GC),
        .s_axi_arready(gc_arready),
        .s_axi_rdata(gc_rdata),
        .s_axi_rresp(gc_rresp),
        .s_axi_rvalid(gc_rvalid),
        .s_axi_rready(rready),
        .gs_distance(gs_distance),
        .gs_speed(gs_speed),
        .gs_direction(gs_direction),
        .gs_var_distance(gs_var_distance),
        .gs_efficiency(gs_efficiency),
        .gs_squitter_en(gs_squitter_en),
        .gs_pulse_rate(gs_pulse_rate),
        .gs_jitter_en(gs_jitter_en),
        .gs_ident(gs_ident),
        .gs_pulse_en(gs_pulse_en),
        .gs_distance_now(gs_distance_now),
        .gs_pulse_width_error(gs_pw_error),
        .gs_pulse_delay_error(gs_pd_error)
    );

    groundStation #(.mod(0)) gs (
        .i_clk_100(clk),
        .i_dme_data(tx_sample),
        .i_pulse_en(gs_pulse_en),
        .i_efficiency(gs_efficiency),
        .i_ident(gs_ident),
        .i_distance(gs_distance),
        .o_distance(gs_distance_now),
        .i_speed(gs_speed),
        .i_pulse_rate(gs_pulse_rate),
        .i_direction(gs_direction),
        .i_var_distance(gs_var_distance),
        .i_squitter_en(gs_squitter_en),
        .i_jitter_en(gs_jitter_en),
        .i_dme_pulse(tx_pulse),
        .o_gs_pulse(gs_pulse),
        .o_gs_out(gs_out),
        .o_pulse_width_error(gs_pw_error),
        .o_pulse_delay_error(gs_pd_error)
    );

    // ------------------------------------------------------------------
    // Monitors
    // ------------------------------------------------------------------
    // Widths and gaps of the interrogation pulses as the station's own
    // demodulator sees them.
    int  gs_width_min = 1 << 30, gs_width_max = 0;
    int  gs_gap_min = 1 << 30, gs_gap_max = 0;
    int  rx_env_peak = 0;
    int  gs_replies = 0;
    int  gs_squitters = 0;
    logic dmod_d = 0;
    int  dmod_count = 0;
    int  dmod_pulses = 0;

    always @(posedge clk) begin
        dmod_d <= gs.dmodOut;
        if (gs.dmodOut)
            dmod_count <= dmod_d ? dmod_count + 1 : 1;
        else
            dmod_count <= dmod_d ? 1 : dmod_count + 1;
        if (dmod_d && !gs.dmodOut) begin
            dmod_pulses <= dmod_pulses + 1;
            if (dmod_count < gs_width_min) gs_width_min <= dmod_count;
            if (dmod_count > gs_width_max) gs_width_max <= dmod_count;
        end
        // Only the gap inside a pair (odd pulse counts are first pulses)
        if (!dmod_d && gs.dmodOut && dmod_pulses % 2 == 1) begin
            if (dmod_count < gs_gap_min) gs_gap_min <= dmod_count;
            if (dmod_count > gs_gap_max) gs_gap_max <= dmod_count;
        end
        if (rx_envelope > rx_env_peak)
            rx_env_peak <= rx_envelope;
        if (gs.rGen.sendReply)
            gs_replies <= gs_replies + 1;
        if (gs.SQGen.sendReply && gs.SQGen.replyState == 0)
            gs_squitters <= gs_squitters + 1;
    end

    // ------------------------------------------------------------------
    // Tasks
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

    task automatic expect_range(input string what, input int got,
                                input int lo, input int hi);
        if (got < lo || got > hi) begin
            $display("FAIL  %s: got %0d, expected %0d to %0d", what, got, lo, hi);
            errors++;
        end else begin
            $display("PASS  %s = %0d (%0d to %0d)", what, got, lo, hi);
        end
    endtask

    task automatic wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    // Clears the aircraft counters and FIFO and the station's error counts.
    task automatic clear_all();
        axi_write(GC, GC_CONTROL, GC_PULSE_EN | 32'h8000_0000);
        axi_write(AC, AC_CONTROL, 32'h8000_0002);
        gs_replies = 0;
        gs_squitters = 0;
    endtask

    // Interrogates for `cycles` with PRF jitter, popping the reply FIFO all
    // the time and writing "time delay" lines to `file`. Returns the number
    // of entries written.
    task automatic run_and_dump(input string file, input int cycles,
                                input int period_cycles, input int jitter_mask,
                                output int entries);
        int fd;
        longint stop_at;
        logic [31:0] status, d, t;
        fd = $fopen(file, "w");
        entries = 0;
        axi_write(AC, AC_TX_PERIOD, period_cycles);
        axi_write(AC, AC_TX_JITTER, jitter_mask);
        axi_write(AC, AC_CONTROL, 32'h3);
        stop_at = $time / 10 + cycles;
        while ($time / 10 < stop_at + period_cycles + jitter_mask) begin
            if ($time / 10 >= stop_at)
                axi_write(AC, AC_CONTROL, 32'h2);
            axi_read(AC, AC_STATUS, status);
            while (!status[1]) begin
                axi_read(AC, AC_REPLY_DELAY, d);
                axi_read(AC, AC_REPLY_TIME, t);
                $fdisplay(fd, "%0d %0d", t, d);
                entries++;
                axi_read(AC, AC_STATUS, status);
            end
            wait_cycles(2000);
        end
        $fclose(fd);
    endtask

    // Sends n interrogations, period_cycles apart, then waits for the replies.
    task automatic interrogate(input int period_cycles, input int n);
        logic [31:0] count;
        axi_write(AC, AC_TX_PERIOD, period_cycles);
        axi_write(AC, AC_CONTROL, 32'h3);
        do begin
            wait_cycles(1000);
            axi_read(AC, AC_TX_COUNT, count);
        end while (count < n);
        axi_write(AC, AC_CONTROL, 32'h2);
        wait_cycles(period_cycles);
    endtask

    // Pops one reply from the aircraft FIFO.
    task automatic pop_reply(output int delay, output bit valid);
        logic [31:0] status, d, t;
        axi_read(AC, AC_STATUS, status);
        valid = !status[1];
        delay = 0;
        if (valid) begin
            axi_read(AC, AC_REPLY_DELAY, d);
            axi_read(AC, AC_REPLY_TIME, t);
            delay = d;
        end
    endtask

    function automatic int gs_one_way_cycles(input int meters);
        logic [31:0] product = 32'(meters) * 32'd334 * 32'd33;
        return int'(product / 32'd32768);
    endfunction

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    int          zero_delay;
    logic [31:0] value;

    task automatic check_distance(input int meters, input int n);
        int delay, sum = 0, got = 0;
        bit valid;
        real measured;
        int expected_delay = zero_delay + ZERO_RANGE_BIAS + 2 * gs_one_way_cycles(meters);
        int period = expected_delay + 20000;

        axi_write(GC, GC_DISTANCE, meters);
        wait_cycles(100); // the station flushes its delay lines on a change
        clear_all();
        interrogate(period, n);
        axi_read(GC, GC_DISTANCE_NOW, value);
        expect_eq($sformatf("%0d m: station distance", meters), value, meters);
        valid = 1;
        while (valid && got < n) begin
            pop_reply(delay, valid);
            if (valid) begin
                expect_range($sformatf("%0d m: reply %0d delay (cycles)", meters, got),
                             delay, expected_delay - DELAY_TOL, expected_delay + DELAY_TOL);
                measured = (delay - zero_delay - ZERO_RANGE_BIAS) * METERS_PER_CYCLE / 2.0;
                expect_range($sformatf("%0d m: reply %0d distance (m)", meters, got),
                             $rtoi(measured + 0.5), meters - 12, meters + 12);
                got++;
            end
        end
        expect_eq($sformatf("%0d m: replies", meters), got, n);
    endtask

    initial begin
        int delay, n, sum;
        bit valid;
        logic [31:0] tx_count, replies, pw_errors, pd_errors;
        int fd_args;

        $display("Checkpoint 4: aircraft DME vs course ground station");
        wait_cycles(10);
        rst_n = 1'b1;
        wait_cycles(10);

        // 1. Format and zero range
        $display("-- 1. Interrogation format, zero range");
        axi_write(GC, GC_DISTANCE, 0);
        wait_cycles(100);
        clear_all();
        interrogate(30000, 4);
        axi_read(AC, AC_TX_COUNT, tx_count);
        axi_read(AC, AC_REPLY_COUNT, replies);
        axi_read(GC, GC_PW_ERRORS, pw_errors);
        axi_read(GC, GC_PD_ERRORS, pd_errors);
        expect_eq("interrogations sent", tx_count, 4);
        expect_eq("station replies", gs_replies, 4);
        expect_eq("aircraft replies decoded", replies, 4);
        expect_eq("station pulse width errors", pw_errors, 0);
        expect_eq("station pulse delay errors", pd_errors, 0);
        expect_range("station-detected pulse width (cycles)", gs_width_min, 650, 749);
        expect_range("station-detected pulse width (cycles)", gs_width_max, 650, 749);
        expect_range("station-detected pulse gap (cycles)", gs_gap_min, 450, 549);
        expect_range("station-detected pulse gap (cycles)", gs_gap_max, 450, 549);
        axi_read(AC, AC_LAST_WIDTH, value);
        $display("INFO  aircraft RX envelope peak %0d, last width %0d cycles", rx_env_peak, value);
        axi_read(AC, AC_LAST_SPACING, value);
        expect_range("aircraft RX reply spacing (cycles)", value, 1195, 1210);
        axi_read(AC, AC_REJECT_COUNT, value);
        expect_eq("aircraft RX rejected pulses", value, 0);

        sum = 0;
        n = 0;
        pop_reply(delay, valid);
        while (valid) begin
            if (n == 0) zero_delay = delay;
            expect_range($sformatf("zero range reply %0d delay", n), delay,
                         zero_delay, zero_delay);
            n++;
            pop_reply(delay, valid);
        end
        expect_eq("zero range replies", n, 4);
        expect_range("zero range delay (cycles)", zero_delay, 5000, 5400);

        // 2. Static distances
        $display("-- 2. Static distances");
        check_distance(1000, 2);
        check_distance(18520, 2);     // 10 NM
        check_distance(92600, 2);     // 50 NM
        check_distance(185200, 2);    // 100 NM
        check_distance(370400, 2);    // 200 NM
        check_distance(389000, 2);    // station limit (FIFO depth)

        // 3. 60% reply efficiency
        $display("-- 3. 60%% reply efficiency");
        axi_write(GC, GC_EFFICIENCY, 60);
        axi_write(GC, GC_DISTANCE, 5000);
        wait_cycles(100);
        clear_all();
        interrogate(30000, 50);
        axi_read(AC, AC_TX_COUNT, tx_count);
        axi_read(AC, AC_REPLY_COUNT, replies);
        $display("INFO  %0d interrogations, %0d replies", tx_count, replies);
        expect_range("replies at 60% efficiency", replies, 20, 40);
        expect_eq("station replies match aircraft replies", gs_replies, replies);
        n = 0;
        pop_reply(delay, valid);
        while (valid) begin
            expect_range($sformatf("60%% reply %0d delay", n), delay,
                         zero_delay + ZERO_RANGE_BIAS + 2 * gs_one_way_cycles(5000) - DELAY_TOL,
                         zero_delay + ZERO_RANGE_BIAS + 2 * gs_one_way_cycles(5000) + DELAY_TOL);
            n++;
            pop_reply(delay, valid);
        end
        expect_eq("replies popped", n, replies);

        // 4. Squitter, static (requirement 4). The interrogation period is
        // above 45000 cycles because after each reply the station sends
        // nothing for 1e8 / pulse rate = 40000 cycles (replyGen.v DELAY).
        $display("-- 4. Squitter 2500 pps, static at 10 km");
        axi_write(GC, GC_EFFICIENCY, 100);
        axi_write(GC, GC_PULSE_RATE, 2500);
        axi_write(GC, GC_DISTANCE, 10000);
        axi_write(GC, GC_CONTROL, GC_PULSE_EN | GC_SQUITTER);
        axi_write(AC, AC_MAX_DELAY, 40000);
        wait_cycles(100);
        clear_all();
        axi_write(GC, GC_CONTROL, GC_PULSE_EN | GC_SQUITTER);
        run_and_dump("squitter_static.txt", 1_500_000, 45000, 8191, n);
        axi_read(AC, AC_TX_COUNT, tx_count);
        axi_read(AC, AC_REPLY_COUNT, replies);
        axi_read(AC, AC_GATED_COUNT, value);
        $display("INFO  %0d interrogations, %0d station replies, %0d squitter pairs sent, %0d pairs decoded, %0d stored, %0d beyond the range gate",
                 tx_count, gs_replies, gs_squitters, replies, n, value);
        expect_range("squitter pairs sent by the station", gs_squitters, 30, 1000);
        expect_range("station replies (some lost to squitter)", gs_replies, tx_count * 8 / 10, tx_count);
        // After each reply the station sends nothing for 40000 cycles, most of
        // this short interrogation period, so few squitter pairs get out.
        expect_range("pairs decoded > replies (squitter received)", replies, gs_replies + 1, 100000);
        expect_range("pairs beyond the range gate", value, 1, 100000);
        expect_eq("stored + gated = decoded", n + value, replies);
        axi_read(AC, AC_STATUS, value);
        expect_eq("FIFO overflow", value & AC_STATUS_OVERFLOW, 0);
        axi_read(GC, GC_PW_ERRORS, pw_errors);
        axi_read(GC, GC_PD_ERRORS, pd_errors);
        expect_eq("station pulse width errors", pw_errors, 0);
        expect_eq("station pulse delay errors", pd_errors, 0);
        fd_args = $fopen("squitter_static.args", "w");
        $fdisplay(fd_args, "squitter_static.txt 500000 %0d 40000 10000",
                  zero_delay + ZERO_RANGE_BIAS);
        $fclose(fd_args);

        // 5. Moving towards the station, 60% efficiency, squitter
        // (requirement 6). countPerKM is forced to 1e6 cycles: one 1 km
        // step every 10 ms, i.e. 100000 m/s in simulated time. The
        // station's step counter has no reset value, so it is started at 0
        // as the FPGA's configuration does. With the counter at 0 the first
        // step comes as soon as motion is enabled: 10 -> 9 km at once, then
        // 8, 7 and 6 km 10 ms apart.
        $display("-- 5. Moving towards, 60%% efficiency, squitter 2500 pps");
        axi_write(GC, GC_EFFICIENCY, 60);
        axi_write(GC, GC_SPEED, 200);
        axi_write(GC, GC_DISTANCE, 10000);
        wait_cycles(100);
        clear_all();
        force gs.distM.countPerKM = 1_000_000;
        force gs.distM.counter = 0;
        wait_cycles(2);
        release gs.distM.counter;
        axi_write(GC, GC_CONTROL, GC_PULSE_EN | GC_SQUITTER | GC_MOTION);
        run_and_dump("squitter_moving.txt", 3_700_000, 45000, 8191, n);
        axi_read(GC, GC_DISTANCE_NOW, value);
        expect_eq("station distance after 4 steps (m)", value, 6000);
        axi_read(AC, AC_TX_COUNT, tx_count);
        axi_read(AC, AC_REPLY_COUNT, replies);
        $display("INFO  %0d interrogations, %0d station replies, %0d squitter pairs, %0d stored",
                 tx_count, gs_replies, gs_squitters, n);
        expect_range("station replies at 60%", gs_replies, tx_count * 4 / 10, tx_count * 8 / 10);
        axi_read(AC, AC_STATUS, value);
        expect_eq("FIFO overflow", value & AC_STATUS_OVERFLOW, 0);
        axi_write(GC, GC_CONTROL, GC_PULSE_EN);
        release gs.distM.countPerKM;
        fd_args = $fopen("squitter_moving.args", "w");
        // Speed: 1000 m per (countPerKM + 1) cycles, towards (negative).
        $fdisplay(fd_args, "squitter_moving.txt 500000 %0d 40000 6000 -99999.9 100000000",
                  zero_delay + ZERO_RANGE_BIAS);
        $fclose(fd_args);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);
        $finish;
    end

    initial begin
        #8_000_000_000;
        $display("FAIL  timeout");
        $finish;
    end
endmodule
