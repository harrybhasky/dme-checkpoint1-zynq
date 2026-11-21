`timescale 1ns/1ps

// Distance model for the DME ground station test equipment.
//
// The range is held as the round-trip propagation delay in clock cycles
// (1 NM = 12.3552 us round trip), with 16 fractional bits so that slow
// aircraft speeds still accumulate. Every update tick the signed velocity
// (Q16 cycles per tick) is added, which models the aircraft flying away
// (positive) or towards (negative) the station. The result is clamped to
// [range_min, range_max]; at_limit reports that the clamp is active.
module dme_range_model #(
    parameter int unsigned UPDATE_CYCLES = 100_000   // 1 ms at 100 MHz
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               motion_enable,
    input  logic               load,
    input  logic [31:0]        load_value,
    input  logic signed [31:0] velocity,
    input  logic [31:0]        range_min,
    input  logic [31:0]        range_max,
    output logic [31:0]        range_cycles,
    output logic               at_limit
);
    localparam int unsigned FRAC_BITS = 16;

    logic [31+FRAC_BITS:0] range_q;
    logic [31:0]           tick_count;

    wire tick = (tick_count == UPDATE_CYCLES - 1);

    // 50-bit signed sum so that underflow below zero is visible.
    wire signed [33+FRAC_BITS:0] next_range =
        $signed({2'b00, range_q}) + 50'(velocity);
    wire signed [33+FRAC_BITS:0] min_q = $signed({2'b00, range_min, {FRAC_BITS{1'b0}}});
    wire signed [33+FRAC_BITS:0] max_q = $signed({2'b00, range_max, {FRAC_BITS{1'b0}}});

    assign range_cycles = range_q[31+FRAC_BITS:FRAC_BITS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            range_q    <= '0;
            tick_count <= 32'd0;
            at_limit   <= 1'b0;
        end else begin
            tick_count <= tick ? 32'd0 : tick_count + 1'b1;

            if (load) begin
                range_q  <= {load_value, {FRAC_BITS{1'b0}}};
                at_limit <= 1'b0;
            end else if (motion_enable && tick) begin
                if (next_range <= min_q) begin
                    range_q  <= min_q[31+FRAC_BITS:0];
                    at_limit <= 1'b1;
                end else if (next_range >= max_q) begin
                    range_q  <= max_q[31+FRAC_BITS:0];
                    at_limit <= 1'b1;
                end else begin
                    range_q  <= next_range[31+FRAC_BITS:0];
                    at_limit <= 1'b0;
                end
            end
        end
    end
endmodule
