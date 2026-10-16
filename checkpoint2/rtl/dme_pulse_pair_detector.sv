`timescale 1ns/1ps

// Validates demodulated pulses and pairs them.
//
// A pulse is valid when its width (rising to falling edge of pulse_in) lies in
// [width_min, width_max]. Two valid pulses form a pair when the spacing
// between their rising edges lies in [spacing_min, spacing_max]. All times are
// in clock cycles of the free-running timestamp counter.
//
// The rising edges of the last HISTORY unpaired valid pulses are kept, and
// each new valid pulse is checked against all of them. A stray pulse (another
// aircraft's reply, a squitter fragment) between the two pulses of a genuine
// pair therefore does not break the pair. An entry is dropped once it is older
// than spacing_max + width_max, because the second pulse is only matched at
// its falling edge.
module dme_pulse_pair_detector #(
    parameter int unsigned HISTORY = 4
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic        clear,
    input  logic        pulse_in,
    input  logic [31:0] timestamp,
    input  logic [31:0] width_min,
    input  logic [31:0] width_max,
    input  logic [31:0] spacing_min,
    input  logic [31:0] spacing_max,
    output logic        pulse_valid,
    output logic        pulse_reject,
    output logic        pair_valid,
    output logic [31:0] pair_timestamp,
    output logic [31:0] pair_spacing,
    output logic [31:0] last_width
);
    logic        pulse_in_d;
    logic        in_pulse;
    logic [31:0] rise_ts;
    logic [31:0] hist_ts    [0:HISTORY-1];
    logic        hist_valid [0:HISTORY-1];

    wire        rise     = pulse_in && !pulse_in_d;
    wire        fall     = !pulse_in && pulse_in_d;
    wire [31:0] width    = timestamp - rise_ts;
    wire        width_ok = (width >= width_min) && (width <= width_max);
    wire [31:0] expiry_age = spacing_max + width_max;

    // Oldest history entry whose spacing to the current pulse is in range.
    logic                       match_found;
    logic [$clog2(HISTORY)-1:0] match_index;
    logic [31:0]                match_spacing;

    always_comb begin
        logic [31:0] spacing;
        match_found   = 1'b0;
        match_index   = '0;
        match_spacing = 32'd0;
        for (int i = HISTORY - 1; i >= 0; i--) begin
            spacing = rise_ts - hist_ts[i];
            if (!match_found && hist_valid[i] &&
                spacing >= spacing_min && spacing <= spacing_max) begin
                match_found   = 1'b1;
                match_index   = ($clog2(HISTORY))'(i);
                match_spacing = spacing;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_in_d     <= 1'b0;
            in_pulse       <= 1'b0;
            rise_ts        <= 32'd0;
            pulse_valid    <= 1'b0;
            pulse_reject   <= 1'b0;
            pair_valid     <= 1'b0;
            pair_timestamp <= 32'd0;
            pair_spacing   <= 32'd0;
            last_width     <= 32'd0;
            for (int i = 0; i < HISTORY; i++) begin
                hist_ts[i]    <= 32'd0;
                hist_valid[i] <= 1'b0;
            end
        end else if (!enable || clear) begin
            pulse_in_d   <= pulse_in;
            in_pulse     <= 1'b0;
            pulse_valid  <= 1'b0;
            pulse_reject <= 1'b0;
            pair_valid   <= 1'b0;
            for (int i = 0; i < HISTORY; i++)
                hist_valid[i] <= 1'b0;
        end else begin
            pulse_in_d   <= pulse_in;
            pulse_valid  <= 1'b0;
            pulse_reject <= 1'b0;
            pair_valid   <= 1'b0;

            // Expire entries that are too old to be the first pulse of a pair.
            for (int i = 0; i < HISTORY; i++)
                if (hist_valid[i] && timestamp - hist_ts[i] > expiry_age)
                    hist_valid[i] <= 1'b0;

            if (rise) begin
                in_pulse <= 1'b1;
                rise_ts  <= timestamp;
            end else if (fall && in_pulse) begin
                in_pulse   <= 1'b0;
                last_width <= width;
                if (!width_ok) begin
                    pulse_reject <= 1'b1;
                end else begin
                    pulse_valid <= 1'b1;
                    if (match_found) begin
                        pair_valid                <= 1'b1;
                        pair_timestamp            <= hist_ts[match_index];
                        pair_spacing              <= match_spacing;
                        hist_valid[match_index]   <= 1'b0;
                    end else begin
                        // Shift in as the newest candidate first pulse.
                        hist_ts[0]    <= rise_ts;
                        hist_valid[0] <= 1'b1;
                        for (int i = 1; i < HISTORY; i++) begin
                            hist_ts[i]    <= hist_ts[i-1];
                            hist_valid[i] <= hist_valid[i-1];
                        end
                    end
                end
            end
        end
    end
endmodule
