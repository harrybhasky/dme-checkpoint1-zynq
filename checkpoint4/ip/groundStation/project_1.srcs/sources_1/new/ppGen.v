`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.08.2025 16:08:47
// Design Name: 
// Module Name: pulsePairGenerator
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


module ppGen (
input             i_rf_clk,
input             i_pulsePairEnable,
output    [11:0]  o_pulse
);
    
    
integer pulseMemAddr = 0; 
reg en,enp,en_d;


always @(posedge i_rf_clk)
begin
    en   <= i_pulsePairEnable;
    en_d <= en;
    enp  <= en & ~en_d;
end

always @(posedge i_rf_clk)
begin
    if(!en_d)
        pulseMemAddr <= 0;
    else if(en_d)//rising edge of pulse readclock
        pulseMemAddr <= pulseMemAddr+1;
end


pulseBRAM mem(
	.i_clk(i_rf_clk),
	.i_addr(pulseMemAddr),
	.o_pulse(o_pulse)
);
  
    
endmodule
