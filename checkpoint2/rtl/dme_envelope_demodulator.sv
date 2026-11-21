`timescale 1ns/1ps

// Non-coherent AM envelope demodulator for the DME pulse pairs.
//
//   sample -> remove DC offset -> |x| -> 1st-order IIR low-pass -> envelope
//   envelope -> comparator with hysteresis -> pulse_out
//
// The IIR is acc += (|x| - acc) >> env_shift, updated once per valid sample,
// so its time constant is about 2^env_shift samples. It removes the 2 MHz
// ripple left after rectifying the 1 MHz carrier.
module dme_envelope_demodulator #(
    parameter int unsigned SAMPLE_WIDTH = 16,
    parameter int unsigned FRAC_BITS    = 16
) (
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           enable,
    input  logic signed [SAMPLE_WIDTH-1:0] sample,
    input  logic                           sample_valid,
    input  logic signed [SAMPLE_WIDTH-1:0] dc_offset,
    input  logic [3:0]                     env_shift,
    input  logic [SAMPLE_WIDTH-1:0]        threshold_high,
    input  logic [SAMPLE_WIDTH-1:0]        threshold_low,
    output logic [SAMPLE_WIDTH-1:0]        envelope,
    output logic                           pulse_out
);
    localparam int unsigned ACC_WIDTH = SAMPLE_WIDTH + FRAC_BITS;
    localparam logic [SAMPLE_WIDTH-1:0] SAMPLE_MAX = '1;

    logic signed [SAMPLE_WIDTH:0]   centered;
    logic [SAMPLE_WIDTH:0]          magnitude;
    logic [SAMPLE_WIDTH-1:0]        rectified;
    logic                           rectified_valid;
    logic [ACC_WIDTH-1:0]           acc;
    logic signed [ACC_WIDTH:0]      acc_error;

    assign centered  = $signed({sample[SAMPLE_WIDTH-1], sample}) -
                       $signed({dc_offset[SAMPLE_WIDTH-1], dc_offset});
    assign magnitude = centered[SAMPLE_WIDTH] ? -centered : centered;
    assign acc_error = $signed({1'b0, rectified, {FRAC_BITS{1'b0}}}) -
                       $signed({1'b0, acc});
    assign envelope  = acc[ACC_WIDTH-1:FRAC_BITS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rectified       <= '0;
            rectified_valid <= 1'b0;
            acc             <= '0;
            pulse_out       <= 1'b0;
        end else if (!enable) begin
            rectified       <= '0;
            rectified_valid <= 1'b0;
            acc             <= '0;
            pulse_out       <= 1'b0;
        end else begin
            // Stage 1: DC removal and rectification, saturated to SAMPLE_WIDTH.
            rectified_valid <= sample_valid;
            if (sample_valid)
                rectified <= magnitude[SAMPLE_WIDTH] ? SAMPLE_MAX :
                             magnitude[SAMPLE_WIDTH-1:0];

            // Stage 2: exponential moving average.
            if (rectified_valid)
                acc <= ACC_WIDTH'($signed({1'b0, acc}) + (acc_error >>> env_shift));

            // Stage 3: hysteresis comparator.
            if (envelope >= threshold_high)
                pulse_out <= 1'b1;
            else if (envelope < threshold_low)
                pulse_out <= 1'b0;
        end
    end
endmodule
