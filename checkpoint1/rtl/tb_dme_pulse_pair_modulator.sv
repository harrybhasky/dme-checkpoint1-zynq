`timescale 1ns/1ps

module tb_dme_pulse_pair_modulator;
    localparam int unsigned CLK_HZ = 1_000_000;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic enable = 1'b0;
    logic carrier_enable = 1'b0;
    logic [31:0] pair_period_us = 32'd10;
    logic pulse_pair, carrier, modulated_out;

    always #500 clk = ~clk; // 1 MHz clock: 1 us per cycle

    dme_pulse_pair_modulator #(
        .CLK_HZ(CLK_HZ),
        .DEFAULT_PAIR_RATE_HZ(10)
    ) dut (
        .clk, .rst_n, .enable, .carrier_enable, .pair_period_us,
        .elapsed_us(), .pulse_pair, .carrier, .modulated_out
    );

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        enable = 1'b1;
        carrier_enable = 1'b1;

        #60_000;
        $display("Checkpoint 1 simulation completed.");
        $finish;
    end
endmodule
