`timescale 1ns/1ps

// Checkpoint 2: DME receive path (pulse demodulator and pair detector) with an
// AXI4-Lite register interface and a FIFO of detected pair timestamps.
//
// Input is either the checkpoint 1 modulated_out (digital loopback, one
// sample per clock) or an ADC sample stream (milestone 4), chosen in CONTROL.
module dme_rx_axi4lite #(
    parameter int unsigned CLK_HZ                  = 100_000_000,
    parameter int unsigned DEFAULT_ENV_SHIFT       = 7,
    parameter int unsigned DEFAULT_THRESHOLD_HIGH  = 5000,
    parameter int unsigned DEFAULT_THRESHOLD_LOW   = 4000,
    parameter int unsigned DEFAULT_WIDTH_MIN_US    = 15,
    parameter int unsigned DEFAULT_WIDTH_MAX_US    = 40,
    parameter int unsigned DEFAULT_SPACING_MIN_US  = 395,
    parameter int unsigned DEFAULT_SPACING_MAX_US  = 405,
    parameter int unsigned FIFO_DEPTH_LOG2         = 4
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

    // Digital loopback from dme_axi4lite/modulated_out (valid every clock)
    input  logic signed [15:0] loopback_sample,
    // ADC sample stream, signed 16-bit (tie off until milestone 4)
    input  logic signed [15:0] adc_sample,
    input  logic               adc_sample_valid,

    output logic [15:0] envelope_out,
    output logic        pulse_detected,
    output logic        pair_detected,
    output logic        irq
);
    localparam int unsigned CLOCKS_PER_US = (CLK_HZ + 500_000) / 1_000_000;
    localparam int unsigned FIFO_DEPTH    = 1 << FIFO_DEPTH_LOG2;

    localparam logic [4:0] REG_CONTROL      = 5'h00;
    localparam logic [4:0] REG_STATUS       = 5'h01;
    localparam logic [4:0] REG_DC_OFFSET    = 5'h02;
    localparam logic [4:0] REG_ENV_SHIFT    = 5'h03;
    localparam logic [4:0] REG_THRESH_HIGH  = 5'h04;
    localparam logic [4:0] REG_THRESH_LOW   = 5'h05;
    localparam logic [4:0] REG_WIDTH_MIN    = 5'h06;
    localparam logic [4:0] REG_WIDTH_MAX    = 5'h07;
    localparam logic [4:0] REG_SPACING_MIN  = 5'h08;
    localparam logic [4:0] REG_SPACING_MAX  = 5'h09;
    localparam logic [4:0] REG_TIMESTAMP    = 5'h0A;
    localparam logic [4:0] REG_PAIR_FIFO    = 5'h0B;
    localparam logic [4:0] REG_PAIR_COUNT   = 5'h0C;
    localparam logic [4:0] REG_PULSE_COUNT  = 5'h0D;
    localparam logic [4:0] REG_REJECT_COUNT = 5'h0E;
    localparam logic [4:0] REG_LAST_WIDTH   = 5'h0F;
    localparam logic [4:0] REG_LAST_SPACING = 5'h10;

    function automatic logic [31:0] apply_wstrb(input logic [31:0] old_value,
                                                input logic [31:0] new_value,
                                                input logic [3:0]  strobe);
        for (int i = 0; i < 4; i++)
            if (strobe[i])
                old_value[i*8 +: 8] = new_value[i*8 +: 8];
        return old_value;
    endfunction

    // Configuration registers
    logic        enable_reg;
    logic        adc_select_reg;
    logic        irq_enable_reg;
    logic        clear_pulse;
    logic [15:0] dc_offset_reg;
    logic [3:0]  env_shift_reg;
    logic [15:0] thresh_high_reg;
    logic [15:0] thresh_low_reg;
    logic [31:0] width_min_reg;
    logic [31:0] width_max_reg;
    logic [31:0] spacing_min_reg;
    logic [31:0] spacing_max_reg;

    // Status
    logic [31:0] timestamp;
    logic [31:0] pair_count;
    logic [31:0] pulse_count;
    logic [31:0] reject_count;
    logic        fifo_overflow;

    // AXI write channel state
    logic        aw_pending;
    logic [6:0]  awaddr_reg;
    logic        w_pending;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;

    // Pair timestamp FIFO
    logic [31:0]              fifo_mem [0:FIFO_DEPTH-1];
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

    wire signed [15:0] rx_sample       = adc_select_reg ? adc_sample : loopback_sample;
    wire               rx_sample_valid = adc_select_reg ? adc_sample_valid : 1'b1;

    wire write_fire = aw_pending && w_pending && !s_axi_bvalid;
    wire read_fire  = s_axi_arvalid && s_axi_arready;
    wire fifo_pop   = read_fire && (s_axi_araddr[6:2] == REG_PAIR_FIFO) && !fifo_empty;
    wire fifo_push  = pair_valid && !fifo_full;

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    assign pair_detected = pair_valid;
    assign irq           = irq_enable_reg && !fifo_empty;

    dme_envelope_demodulator #(
        .SAMPLE_WIDTH(16)
    ) demodulator (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .enable(enable_reg),
        .sample(rx_sample),
        .sample_valid(rx_sample_valid),
        .dc_offset(dc_offset_reg),
        .env_shift(env_shift_reg),
        .threshold_high(thresh_high_reg),
        .threshold_low(thresh_low_reg),
        .envelope(envelope_out),
        .pulse_out(pulse_detected)
    );

    dme_pulse_pair_detector detector (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .enable(enable_reg),
        .clear(clear_pulse),
        .pulse_in(pulse_detected),
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

    // Free-running timestamp, shared timebase for pair timestamps.
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            timestamp <= 32'd0;
        else
            timestamp <= timestamp + 1'b1;
    end

    // Counters and FIFO
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || clear_pulse) begin
            pair_count    <= 32'd0;
            pulse_count   <= 32'd0;
            reject_count  <= 32'd0;
            fifo_overflow <= 1'b0;
            fifo_wr_ptr   <= '0;
            fifo_rd_ptr   <= '0;
        end else begin
            if (pair_valid)   pair_count   <= pair_count + 1'b1;
            if (pulse_valid)  pulse_count  <= pulse_count + 1'b1;
            if (pulse_reject) reject_count <= reject_count + 1'b1;
            if (pair_valid && fifo_full) fifo_overflow <= 1'b1;

            if (fifo_push) begin
                fifo_mem[fifo_wr_ptr[FIFO_DEPTH_LOG2-1:0]] <= pair_timestamp;
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            end
            if (fifo_pop)
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
        end
    end

    // AXI4-Lite register interface
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            enable_reg      <= 1'b0;
            adc_select_reg  <= 1'b0;
            irq_enable_reg  <= 1'b0;
            clear_pulse     <= 1'b0;
            dc_offset_reg   <= 16'd0;
            env_shift_reg   <= 4'(DEFAULT_ENV_SHIFT);
            thresh_high_reg <= 16'(DEFAULT_THRESHOLD_HIGH);
            thresh_low_reg  <= 16'(DEFAULT_THRESHOLD_LOW);
            width_min_reg   <= DEFAULT_WIDTH_MIN_US * CLOCKS_PER_US;
            width_max_reg   <= DEFAULT_WIDTH_MAX_US * CLOCKS_PER_US;
            spacing_min_reg <= DEFAULT_SPACING_MIN_US * CLOCKS_PER_US;
            spacing_max_reg <= DEFAULT_SPACING_MAX_US * CLOCKS_PER_US;
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
                            enable_reg     <= wdata_reg[0];
                            adc_select_reg <= wdata_reg[1];
                            irq_enable_reg <= wdata_reg[2];
                        end
                        if (wstrb_reg[3] && wdata_reg[31])
                            clear_pulse <= 1'b1;
                    end
                    REG_DC_OFFSET:   dc_offset_reg   <= 16'(apply_wstrb({16'd0, dc_offset_reg}, wdata_reg, wstrb_reg));
                    REG_ENV_SHIFT:   if (wstrb_reg[0]) env_shift_reg <= wdata_reg[3:0];
                    REG_THRESH_HIGH: thresh_high_reg <= 16'(apply_wstrb({16'd0, thresh_high_reg}, wdata_reg, wstrb_reg));
                    REG_THRESH_LOW:  thresh_low_reg  <= 16'(apply_wstrb({16'd0, thresh_low_reg}, wdata_reg, wstrb_reg));
                    REG_WIDTH_MIN:   width_min_reg   <= apply_wstrb(width_min_reg, wdata_reg, wstrb_reg);
                    REG_WIDTH_MAX:   width_max_reg   <= apply_wstrb(width_max_reg, wdata_reg, wstrb_reg);
                    REG_SPACING_MIN: spacing_min_reg <= apply_wstrb(spacing_min_reg, wdata_reg, wstrb_reg);
                    REG_SPACING_MAX: spacing_max_reg <= apply_wstrb(spacing_max_reg, wdata_reg, wstrb_reg);
                    REG_STATUS, REG_TIMESTAMP, REG_PAIR_FIFO, REG_PAIR_COUNT,
                    REG_PULSE_COUNT, REG_REJECT_COUNT, REG_LAST_WIDTH,
                    REG_LAST_SPACING: ; // read-only
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
                    REG_CONTROL:      s_axi_rdata <= {29'd0, irq_enable_reg, adc_select_reg, enable_reg};
                    REG_STATUS:       s_axi_rdata <= {envelope_out, 3'd0, 5'(fifo_count),
                                                      4'd0, fifo_overflow, fifo_full,
                                                      fifo_empty, pulse_detected};
                    REG_DC_OFFSET:    s_axi_rdata <= {{16{dc_offset_reg[15]}}, dc_offset_reg};
                    REG_ENV_SHIFT:    s_axi_rdata <= {28'd0, env_shift_reg};
                    REG_THRESH_HIGH:  s_axi_rdata <= {16'd0, thresh_high_reg};
                    REG_THRESH_LOW:   s_axi_rdata <= {16'd0, thresh_low_reg};
                    REG_WIDTH_MIN:    s_axi_rdata <= width_min_reg;
                    REG_WIDTH_MAX:    s_axi_rdata <= width_max_reg;
                    REG_SPACING_MIN:  s_axi_rdata <= spacing_min_reg;
                    REG_SPACING_MAX:  s_axi_rdata <= spacing_max_reg;
                    REG_TIMESTAMP:    s_axi_rdata <= timestamp;
                    REG_PAIR_FIFO:    s_axi_rdata <= fifo_empty ? 32'd0 :
                                                     fifo_mem[fifo_rd_ptr[FIFO_DEPTH_LOG2-1:0]];
                    REG_PAIR_COUNT:   s_axi_rdata <= pair_count;
                    REG_PULSE_COUNT:  s_axi_rdata <= pulse_count;
                    REG_REJECT_COUNT: s_axi_rdata <= reject_count;
                    REG_LAST_WIDTH:   s_axi_rdata <= last_width;
                    REG_LAST_SPACING: s_axi_rdata <= pair_spacing;
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
