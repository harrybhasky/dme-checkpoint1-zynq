`timescale 1ns/1ps

// Checkpoint 4: aircraft DME interrogator for the course ground station IP.
//
//   tx_sample ──► groundStation/i_dme_data      (12-bit, 10 MHz carrier)
//   rx_sample ◄── groundStation/o_gs_out
//
// Transmit: dme_interrogator_tx (7 us pulses, 12 us apart, 10 MHz carrier).
// Receive: the checkpoint 2 envelope demodulator and pair detector, with
// their thresholds and windows set for the ground station's replies.
// Ranging: every detected reply pair is stored in a FIFO with its delay, in
// clock cycles, from the start of the latest interrogation sent before the
// reply's first pulse. Software turns the delay into distance and speed.
// Pairs later than MAX_DELAY (beyond the longest range) are counted but not
// stored, so squitter between interrogations cannot fill the FIFO.
module dme_aircraft_axi4lite #(
    parameter int unsigned DEFAULT_PERIOD_CYCLES  = 3_333_333, // 30 pairs/s
    parameter int unsigned DEFAULT_ENV_SHIFT      = 4,
    parameter int unsigned DEFAULT_THRESHOLD_HIGH = 10000,
    parameter int unsigned DEFAULT_THRESHOLD_LOW  = 8000,
    parameter int unsigned DEFAULT_WIDTH_MIN      = 400,
    parameter int unsigned DEFAULT_WIDTH_MAX      = 650,
    parameter int unsigned DEFAULT_SPACING_MIN    = 1150,
    parameter int unsigned DEFAULT_SPACING_MAX    = 1250,
    // Range gate: pairs later than this after the interrogation are not
    // stored. 270000 cycles is just beyond the station's 389 km limit.
    parameter int unsigned DEFAULT_MAX_DELAY      = 270_000,
    parameter int unsigned FIFO_DEPTH_LOG2        = 6
) (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    input  logic [6:0]  s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [6:0]  s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // To groundStation i_dme_data (and i_dme_pulse if its mod = 1)
    output logic signed [11:0] tx_sample,
    output logic               tx_pulse,
    // From groundStation o_gs_out
    input  logic signed [11:0] rx_sample,

    // Debug / ILA
    output logic        tx_start,
    output logic [15:0] rx_envelope,
    output logic        rx_pulse,
    output logic        reply_detected,
    output logic        irq
);
    localparam int unsigned FIFO_DEPTH = 1 << FIFO_DEPTH_LOG2;

    localparam logic [4:0] REG_CONTROL      = 5'h00;
    localparam logic [4:0] REG_STATUS       = 5'h01;
    localparam logic [4:0] REG_TX_PERIOD    = 5'h02;
    localparam logic [4:0] REG_TX_JITTER    = 5'h03;
    localparam logic [4:0] REG_ENV_SHIFT    = 5'h04;
    localparam logic [4:0] REG_THRESH_HIGH  = 5'h05;
    localparam logic [4:0] REG_THRESH_LOW   = 5'h06;
    localparam logic [4:0] REG_WIDTH_MIN    = 5'h07;
    localparam logic [4:0] REG_WIDTH_MAX    = 5'h08;
    localparam logic [4:0] REG_SPACING_MIN  = 5'h09;
    localparam logic [4:0] REG_SPACING_MAX  = 5'h0A;
    localparam logic [4:0] REG_TIMESTAMP    = 5'h0B;
    localparam logic [4:0] REG_TX_TIMESTAMP = 5'h0C;
    localparam logic [4:0] REG_TX_COUNT     = 5'h0D;
    localparam logic [4:0] REG_REPLY_DELAY  = 5'h0E;
    localparam logic [4:0] REG_REPLY_TIME   = 5'h0F;
    localparam logic [4:0] REG_REPLY_COUNT  = 5'h10;
    localparam logic [4:0] REG_PULSE_COUNT  = 5'h11;
    localparam logic [4:0] REG_REJECT_COUNT = 5'h12;
    localparam logic [4:0] REG_LAST_WIDTH   = 5'h13;
    localparam logic [4:0] REG_LAST_SPACING = 5'h14;
    localparam logic [4:0] REG_MAX_DELAY    = 5'h15;
    localparam logic [4:0] REG_GATED_COUNT  = 5'h16;

    function automatic logic [31:0] apply_wstrb(input logic [31:0] old_value,
                                                input logic [31:0] new_value,
                                                input logic [3:0]  strobe);
        for (int i = 0; i < 4; i++)
            if (strobe[i])
                old_value[i*8 +: 8] = new_value[i*8 +: 8];
        return old_value;
    endfunction

    // Configuration
    logic        tx_enable_reg;
    logic        rx_enable_reg;
    logic        irq_enable_reg;
    logic        clear_pulse;
    logic [31:0] period_reg;
    logic [31:0] jitter_reg;
    logic [3:0]  env_shift_reg;
    logic [15:0] thresh_high_reg;
    logic [15:0] thresh_low_reg;
    logic [31:0] width_min_reg;
    logic [31:0] width_max_reg;
    logic [31:0] spacing_min_reg;
    logic [31:0] spacing_max_reg;
    logic [31:0] max_delay_reg;

    // Status
    logic [31:0] timestamp;
    logic [31:0] tx_ts;
    logic [31:0] tx_ts_prev;
    logic [31:0] tx_count;
    logic [31:0] reply_count;
    logic [31:0] pulse_count;
    logic [31:0] reject_count;
    logic [31:0] gated_count;
    logic        fifo_overflow;

    // AXI write channel state
    logic        aw_pending;
    logic [6:0]  awaddr_reg;
    logic        w_pending;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;

    // Reply FIFO: pair timestamp and its delay from the interrogation
    logic [31:0]              time_mem  [0:FIFO_DEPTH-1];
    logic [31:0]              delay_mem [0:FIFO_DEPTH-1];
    logic [FIFO_DEPTH_LOG2:0] fifo_wr_ptr;
    logic [FIFO_DEPTH_LOG2:0] fifo_rd_ptr;
    wire  [FIFO_DEPTH_LOG2:0] fifo_count = fifo_wr_ptr - fifo_rd_ptr;
    wire                      fifo_empty = (fifo_count == 0);
    wire                      fifo_full  = fifo_count[FIFO_DEPTH_LOG2];

    // Detector outputs
    logic        pulse_valid;
    logic        pulse_reject;
    logic        pair_valid;
    logic [31:0] pair_timestamp;
    logic [31:0] pair_spacing;
    logic [31:0] last_width;

    // A reply belongs to the latest interrogation sent before its first
    // pulse. If a new one started while the reply was being received, use
    // the previous one.
    wire [31:0] pair_delay = ($signed(pair_timestamp - tx_ts) >= 0) ?
                             pair_timestamp - tx_ts : pair_timestamp - tx_ts_prev;

    wire write_fire = aw_pending && w_pending && !s_axi_bvalid;
    wire read_fire  = s_axi_arvalid && s_axi_arready;
    wire fifo_pop   = read_fire && (s_axi_araddr[6:2] == REG_REPLY_TIME) && !fifo_empty;
    wire in_range   = (pair_delay <= max_delay_reg);
    wire fifo_push  = pair_valid && in_range && !fifo_full;

    assign s_axi_awready  = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready   = !w_pending && !s_axi_bvalid;
    assign s_axi_arready  = !s_axi_rvalid;
    assign reply_detected = pair_valid;
    assign irq            = irq_enable_reg && !fifo_empty;

    dme_interrogator_tx transmitter (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .enable(tx_enable_reg),
        .period_cycles(period_reg),
        .jitter_mask(jitter_reg),
        .tx_sample(tx_sample),
        .tx_pulse(tx_pulse),
        .tx_start(tx_start)
    );

    // 12-bit samples into the 16-bit checkpoint 2 demodulator, MSB aligned.
    dme_envelope_demodulator #(
        .SAMPLE_WIDTH(16)
    ) demodulator (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .enable(rx_enable_reg),
        .sample({rx_sample, 4'd0}),
        .sample_valid(1'b1),
        .dc_offset(16'sd0),
        .env_shift(env_shift_reg),
        .threshold_high(thresh_high_reg),
        .threshold_low(thresh_low_reg),
        .envelope(rx_envelope),
        .pulse_out(rx_pulse)
    );

    dme_pulse_pair_detector detector (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .enable(rx_enable_reg),
        .clear(clear_pulse),
        .pulse_in(rx_pulse),
        .timestamp(timestamp),
        .width_min(width_min_reg),
        .width_max(width_max_reg),
        .spacing_min(spacing_min_reg),
        .spacing_max(spacing_max_reg),
        .pulse_valid(pulse_valid),
        .pulse_reject(pulse_reject),
        .pair_valid(pair_valid),
        .pair_timestamp(pair_timestamp),
        .pair_spacing(pair_spacing),
        .last_width(last_width)
    );

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            timestamp <= 32'd0;
        else
            timestamp <= timestamp + 1'b1;
    end

    // Interrogation timestamps
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || clear_pulse) begin
            tx_ts      <= 32'd0;
            tx_ts_prev <= 32'd0;
            tx_count   <= 32'd0;
        end else if (tx_start) begin
            tx_ts      <= timestamp;
            tx_ts_prev <= tx_ts;
            tx_count   <= tx_count + 1'b1;
        end
    end

    // Counters and reply FIFO
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || clear_pulse) begin
            reply_count   <= 32'd0;
            pulse_count   <= 32'd0;
            reject_count  <= 32'd0;
            gated_count   <= 32'd0;
            fifo_overflow <= 1'b0;
            fifo_wr_ptr   <= '0;
            fifo_rd_ptr   <= '0;
        end else begin
            if (pair_valid)   reply_count  <= reply_count + 1'b1;
            if (pulse_valid)  pulse_count  <= pulse_count + 1'b1;
            if (pulse_reject) reject_count <= reject_count + 1'b1;
            if (pair_valid && !in_range) gated_count <= gated_count + 1'b1;
            if (pair_valid && in_range && fifo_full) fifo_overflow <= 1'b1;

            if (fifo_push) begin
                time_mem[fifo_wr_ptr[FIFO_DEPTH_LOG2-1:0]]  <= pair_timestamp;
                delay_mem[fifo_wr_ptr[FIFO_DEPTH_LOG2-1:0]] <= pair_delay;
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            end
            if (fifo_pop)
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
        end
    end

    // AXI4-Lite register interface
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            tx_enable_reg   <= 1'b0;
            rx_enable_reg   <= 1'b0;
            irq_enable_reg  <= 1'b0;
            clear_pulse     <= 1'b0;
            period_reg      <= DEFAULT_PERIOD_CYCLES;
            jitter_reg      <= 32'd0;
            env_shift_reg   <= 4'(DEFAULT_ENV_SHIFT);
            thresh_high_reg <= 16'(DEFAULT_THRESHOLD_HIGH);
            thresh_low_reg  <= 16'(DEFAULT_THRESHOLD_LOW);
            width_min_reg   <= DEFAULT_WIDTH_MIN;
            width_max_reg   <= DEFAULT_WIDTH_MAX;
            spacing_min_reg <= DEFAULT_SPACING_MIN;
            spacing_max_reg <= DEFAULT_SPACING_MAX;
            max_delay_reg   <= DEFAULT_MAX_DELAY;
            aw_pending      <= 1'b0;
            w_pending       <= 1'b0;
            awaddr_reg      <= 7'd0;
            wdata_reg       <= 32'd0;
            wstrb_reg       <= 4'd0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= 32'd0;
            s_axi_rresp     <= 2'b00;
        end else begin
            clear_pulse <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending <= 1'b1;
                awaddr_reg <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending <= 1'b1;
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
            end

            if (write_fire) begin
                s_axi_bresp <= 2'b00;
                case (awaddr_reg[6:2])
                    REG_CONTROL: begin
                        if (wstrb_reg[0]) begin
                            tx_enable_reg  <= wdata_reg[0];
                            rx_enable_reg  <= wdata_reg[1];
                            irq_enable_reg <= wdata_reg[2];
                        end
                        if (wstrb_reg[3] && wdata_reg[31])
                            clear_pulse <= 1'b1;
                    end
                    REG_TX_PERIOD:   period_reg      <= apply_wstrb(period_reg, wdata_reg, wstrb_reg);
                    REG_TX_JITTER:   jitter_reg      <= apply_wstrb(jitter_reg, wdata_reg, wstrb_reg);
                    REG_ENV_SHIFT:   if (wstrb_reg[0]) env_shift_reg <= wdata_reg[3:0];
                    REG_THRESH_HIGH: thresh_high_reg <= 16'(apply_wstrb({16'd0, thresh_high_reg}, wdata_reg, wstrb_reg));
                    REG_THRESH_LOW:  thresh_low_reg  <= 16'(apply_wstrb({16'd0, thresh_low_reg}, wdata_reg, wstrb_reg));
                    REG_WIDTH_MIN:   width_min_reg   <= apply_wstrb(width_min_reg, wdata_reg, wstrb_reg);
                    REG_WIDTH_MAX:   width_max_reg   <= apply_wstrb(width_max_reg, wdata_reg, wstrb_reg);
                    REG_SPACING_MIN: spacing_min_reg <= apply_wstrb(spacing_min_reg, wdata_reg, wstrb_reg);
                    REG_SPACING_MAX: spacing_max_reg <= apply_wstrb(spacing_max_reg, wdata_reg, wstrb_reg);
                    REG_MAX_DELAY:   max_delay_reg   <= apply_wstrb(max_delay_reg, wdata_reg, wstrb_reg);
                    REG_STATUS, REG_TIMESTAMP, REG_TX_TIMESTAMP, REG_TX_COUNT,
                    REG_REPLY_DELAY, REG_REPLY_TIME, REG_REPLY_COUNT,
                    REG_PULSE_COUNT, REG_REJECT_COUNT, REG_LAST_WIDTH,
                    REG_LAST_SPACING, REG_GATED_COUNT: ; // read-only
                    default: s_axi_bresp <= 2'b10;
                endcase
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (read_fire) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                case (s_axi_araddr[6:2])
                    REG_CONTROL:      s_axi_rdata <= {29'd0, irq_enable_reg, rx_enable_reg, tx_enable_reg};
                    REG_STATUS:       s_axi_rdata <= {rx_envelope, 1'b0, 7'(fifo_count),
                                                      4'd0, fifo_overflow, fifo_full,
                                                      fifo_empty, rx_pulse};
                    REG_TX_PERIOD:    s_axi_rdata <= period_reg;
                    REG_TX_JITTER:    s_axi_rdata <= jitter_reg;
                    REG_ENV_SHIFT:    s_axi_rdata <= {28'd0, env_shift_reg};
                    REG_THRESH_HIGH:  s_axi_rdata <= {16'd0, thresh_high_reg};
                    REG_THRESH_LOW:   s_axi_rdata <= {16'd0, thresh_low_reg};
                    REG_WIDTH_MIN:    s_axi_rdata <= width_min_reg;
                    REG_WIDTH_MAX:    s_axi_rdata <= width_max_reg;
                    REG_SPACING_MIN:  s_axi_rdata <= spacing_min_reg;
                    REG_SPACING_MAX:  s_axi_rdata <= spacing_max_reg;
                    REG_TIMESTAMP:    s_axi_rdata <= timestamp;
                    REG_TX_TIMESTAMP: s_axi_rdata <= tx_ts;
                    REG_TX_COUNT:     s_axi_rdata <= tx_count;
                    REG_REPLY_DELAY:  s_axi_rdata <= fifo_empty ? 32'd0 :
                                                     delay_mem[fifo_rd_ptr[FIFO_DEPTH_LOG2-1:0]];
                    REG_REPLY_TIME:   s_axi_rdata <= fifo_empty ? 32'd0 :
                                                     time_mem[fifo_rd_ptr[FIFO_DEPTH_LOG2-1:0]];
                    REG_REPLY_COUNT:  s_axi_rdata <= reply_count;
                    REG_PULSE_COUNT:  s_axi_rdata <= pulse_count;
                    REG_REJECT_COUNT: s_axi_rdata <= reject_count;
                    REG_LAST_WIDTH:   s_axi_rdata <= last_width;
                    REG_LAST_SPACING: s_axi_rdata <= pair_spacing;
                    REG_MAX_DELAY:    s_axi_rdata <= max_delay_reg;
                    REG_GATED_COUNT:  s_axi_rdata <= gated_count;
                    default: begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= 2'b10;
                    end
                endcase
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end
endmodule
