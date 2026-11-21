`timescale 1ns/1ps

// Aircraft interrogation transmitter, final-project format:
//
//   pulse width   7 us half-sine (700 samples at 100 MHz)
//   pair spacing  12 us, rising edge to rising edge
//   carrier       10 MHz, exactly 10 samples per cycle
//   output        12-bit signed samples, one per clock, the same scale as
//                 the course ground station (peak about 2046)
//
// A new pair starts every period_cycles clocks, plus a random 0 to
// jitter_mask extra cycles when jitter_mask is non-zero. Random PRF jitter
// is what lets an interrogator separate its own replies from squitter and
// other aircraft's replies, which do not move with it.
//
// Clearing enable stops new pairs; a pair already started is finished.
//
// tx_start pulses for one clock together with the first sample of the
// first pulse at tx_sample. It is the time reference for range.
module dme_interrogator_tx #(
    parameter int unsigned PULSE_SAMPLES = 700,
    parameter int unsigned PAIR_SPACING  = 1200,
    parameter int unsigned MIN_PERIOD    = 2000
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               enable,
    input  logic [31:0]        period_cycles,
    input  logic [31:0]        jitter_mask,
    output logic signed [11:0] tx_sample,
    output logic               tx_pulse,
    output logic               tx_start
);
    localparam int unsigned PAIR_SAMPLES = PAIR_SPACING + PULSE_SAMPLES;

    // 10 MHz cosine at 100 MHz, amplitude 2047: round(2047 cos(2 pi k / 10)).
    function automatic logic signed [11:0] carrier_lut(input logic [3:0] k);
        case (k)
            4'd0:    return 12'sd2047;
            4'd1:    return 12'sd1656;
            4'd2:    return 12'sd633;
            4'd3:    return -12'sd633;
            4'd4:    return -12'sd1656;
            4'd5:    return -12'sd2047;
            4'd6:    return -12'sd1656;
            4'd7:    return -12'sd633;
            4'd8:    return 12'sd633;
            default: return 12'sd1656;
        endcase
    endfunction

    logic        active;
    logic [11:0] pos;
    logic [31:0] period_count;
    logic [31:0] current_period;
    logic [15:0] lfsr;
    logic [3:0]  carrier_phase;

    wire in_pulse_1 = active && (pos < PULSE_SAMPLES);
    wire in_pulse_2 = active && (pos >= PAIR_SPACING) && (pos < PAIR_SAMPLES);
    wire [11:0] rom_index = in_pulse_1 ? pos : pos - 12'(PAIR_SPACING);
    wire [31:0] base_period = (period_cycles < MIN_PERIOD) ? MIN_PERIOD : period_cycles;
    wire        start_pair  = enable && !(active && pos != PAIR_SAMPLES - 1) &&
                              (period_count >= current_period - 1);

    // Pipeline: stage 1 ROM and carrier lookup, stage 2 multiply.
    logic [11:0]        envelope;
    logic signed [11:0] carrier;
    logic               key_1, start_1;
    logic signed [24:0] product;
    logic               key_2, start_2;

    dme_halfsine_rom rom (
        .clk(clk),
        .addr((in_pulse_1 || in_pulse_2) ? rom_index[9:0] : 10'd1023),
        .data(envelope)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active         <= 1'b0;
            pos            <= 12'd0;
            period_count   <= 32'd0;
            current_period <= 32'd0;
            lfsr           <= 16'hACE1;
            carrier_phase  <= 4'd0;
            carrier        <= 12'sd0;
            key_1          <= 1'b0;
            start_1        <= 1'b0;
            product        <= 25'sd0;
            key_2          <= 1'b0;
            start_2        <= 1'b0;
        end else begin
            carrier_phase <= (carrier_phase == 4'd9) ? 4'd0 : carrier_phase + 1'b1;
            carrier       <= carrier_lut(carrier_phase);

            if (!enable) begin
                // Finish the pair being sent, so no pulse is ever cut short.
                period_count <= 32'd0;
                // The first pair goes out on the clock after enable.
                current_period <= 32'd1;
                if (active) begin
                    if (pos == PAIR_SAMPLES - 1)
                        active <= 1'b0;
                    else
                        pos <= pos + 1'b1;
                end
            end else if (start_pair) begin
                active         <= 1'b1;
                pos            <= 12'd0;
                period_count   <= 32'd0;
                current_period <= base_period + (32'(lfsr) & jitter_mask);
                lfsr           <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            end else begin
                period_count <= period_count + 1'b1;
                if (active) begin
                    if (pos == PAIR_SAMPLES - 1)
                        active <= 1'b0;
                    else
                        pos <= pos + 1'b1;
                end
            end

            key_1   <= in_pulse_1 || in_pulse_2;
            start_1 <= active && (pos == 12'd0);

            product <= $signed({1'b0, envelope}) * carrier;
            key_2   <= key_1;
            start_2 <= start_1;
        end
    end

    // Divide by 2048, as the ground station's mixer does.
    assign tx_sample = product[22:11];
    assign tx_pulse  = key_2;
    assign tx_start  = start_2;
endmodule
