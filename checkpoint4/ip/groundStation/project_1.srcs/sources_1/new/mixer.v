`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.11.2026 13:02:18
// Design Name: 
// Module Name: mixer
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mixer(
input          i_clk,
input signed [11:0]   i_baseband,
input signed [11:0]   i_carrier,
output       [11:0]  o_tx_data
);

reg signed [23:0] tmp;

always @(posedge i_clk)
begin
    tmp <= i_baseband*i_carrier;
end

assign o_tx_data = tmp[22:11];

endmodule
