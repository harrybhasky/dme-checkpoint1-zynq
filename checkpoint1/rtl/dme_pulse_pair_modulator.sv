`timescale 1ns/1ps

module dme_pulse_pair_modulator #(
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned CARRIER_HZ = 1_000_000,
    parameter int unsigned PULSE_WIDTH_US = 50,
    parameter int unsigned INTER_PULSE_DELAY_US = 350,
    parameter int unsigned DEFAULT_PAIR_RATE_HZ = 30
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic        carrier_enable,
    input  logic [31:0] pair_period_us,
    output logic [31:0] elapsed_us,
    output logic        pulse_pair,
    output logic        carrier,
    output logic        modulated_out
);
    localparam int unsigned CLOCKS_PER_US =
        (CLK_HZ + 500_000) / 1_000_000;
    localparam int unsigned DEFAULT_PERIOD_US =
        (DEFAULT_PAIR_RATE_HZ == 0) ? 33_333 :
        ((1_000_000 + DEFAULT_PAIR_RATE_HZ / 2) / DEFAULT_PAIR_RATE_HZ);
    localparam logic [31:0] DDS_PHASE_INCREMENT =
        (CARRIER_HZ * 64'd4_294_967_296 + CLK_HZ / 2) / CLK_HZ;

    typedef enum logic [2:0] {
        S_IDLE,
        S_PULSE_1,
        S_GAP,
        S_PULSE_2,
        S_WAIT
    } state_t;

    state_t state;
    logic [31:0] us_clock_count;
    logic [31:0] state_elapsed_us;
    logic [31:0] pair_elapsed_us;
    logic [31:0] dds_phase;

    wire us_tick = (CLOCKS_PER_US <= 1) ||
                   (us_clock_count == CLOCKS_PER_US - 1);
    wire [31:0] minimum_period_us =
        PULSE_WIDTH_US + INTER_PULSE_DELAY_US + PULSE_WIDTH_US;
    wire [31:0] active_period_us =
        (pair_period_us < minimum_period_us) ?
        minimum_period_us : pair_period_us;

    assign elapsed_us = pair_elapsed_us;
    assign pulse_pair = (state == S_PULSE_1) || (state == S_PULSE_2);
    assign carrier = dds_phase[31];
    assign modulated_out = pulse_pair && carrier_enable && dds_phase[31];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            us_clock_count    <= 32'd0;
            state_elapsed_us  <= 32'd0;
            pair_elapsed_us   <= 32'd0;
            dds_phase         <= 32'd0;
        end else begin
            if (!enable) begin
                state            <= S_IDLE;
                us_clock_count   <= 32'd0;
                state_elapsed_us <= 32'd0;
                pair_elapsed_us  <= 32'd0;
            end else begin
                if (us_tick) begin
                    us_clock_count <= 32'd0;

                    if (pair_elapsed_us >= active_period_us - 1)
                        pair_elapsed_us <= 32'd0;
                    else
                        pair_elapsed_us <= pair_elapsed_us + 1'b1;

                    case (state)
                        S_IDLE: begin
                            state            <= S_PULSE_1;
                            state_elapsed_us <= 32'd0;
                        end
                        S_PULSE_1: begin
                            if (state_elapsed_us >= PULSE_WIDTH_US - 1) begin
                                state            <= S_GAP;
                                state_elapsed_us <= 32'd0;
                            end else begin
                                state_elapsed_us <= state_elapsed_us + 1'b1;
                            end
                        end
                        S_GAP: begin
                            if (state_elapsed_us >= INTER_PULSE_DELAY_US - 1) begin
                                state            <= S_PULSE_2;
                                state_elapsed_us <= 32'd0;
                            end else begin
                                state_elapsed_us <= state_elapsed_us + 1'b1;
                            end
                        end
                        S_PULSE_2: begin
                            if (state_elapsed_us >= PULSE_WIDTH_US - 1) begin
                                state            <= S_WAIT;
                                state_elapsed_us <= 32'd0;
                            end else begin
                                state_elapsed_us <= state_elapsed_us + 1'b1;
                            end
                        end
                        S_WAIT: begin
                            if (pair_elapsed_us >= active_period_us - 1) begin
                                state            <= S_PULSE_1;
                                state_elapsed_us <= 32'd0;
                            end
                        end
                        default: state <= S_IDLE;
                    endcase
                end else if (CLOCKS_PER_US > 1) begin
                    us_clock_count <= us_clock_count + 1'b1;
                end

                dds_phase <= dds_phase + DDS_PHASE_INCREMENT;
            end
        end
    end

endmodule
