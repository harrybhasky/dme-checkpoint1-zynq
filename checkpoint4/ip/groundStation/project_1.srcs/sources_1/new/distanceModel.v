`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/01/2026 05:05:23 PM
// Design Name: 
// Module Name: distanceModel
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


module distanceModel #(parameter MAX_DISTANCE=1000000)(
input               i_clk,
input				i_en,
input      [7:0]    i_speed,     //speed in m/s
input      [19:0]   i_distance,  //distance in meters
input				i_direction, //0-towards gs, 1-away gs
output reg [19:0]   o_distance   //distance in meters
);


integer counter;
integer countPerKM; 
reg [19:0] prevDistance=0;
wire div_valid;
wire [23:0] seconds_for_km;

initial
	o_distance = 0;
	
	
div_gen_1 divider (
  .aclk(i_clk),                                      // input wire aclk
  .s_axis_divisor_tvalid(1),    // input wire s_axis_divisor_tvalid
  .s_axis_divisor_tdata(i_speed),      // input wire [7 : 0] s_axis_divisor_tdata
  .s_axis_dividend_tvalid(1),  // input wire s_axis_dividend_tvalid
  .s_axis_dividend_tdata(1000),    // input wire [15 : 0] s_axis_dividend_tdata
  .m_axis_dout_tvalid(div_valid),          // output wire m_axis_dout_tvalid
  .m_axis_dout_tdata(seconds_for_km)            // output wire [23 : 0] m_axis_dout_tdata
);	

always @(posedge i_clk)
begin	
    if(div_valid) 
		//100000000 100MHz clock cycles in a second
		countPerKM = 100000000*seconds_for_km[19:8];//Drop 8 bits fractions
end		

always @(posedge i_clk)
begin
	if(i_en)
	begin
		if(counter == 0)
			counter <= countPerKM;
		else
			counter <= counter - 1;
	end
end

always @(posedge i_clk)
begin
	prevDistance <= i_distance;
	if(i_distance != prevDistance)
		o_distance <= i_distance;
    else if((counter == 0) & i_en)
	begin
		if(~i_direction)
		begin
			if(o_distance >= 1000)
			begin
				o_distance <= o_distance-1000;
			end
		end
		else
		begin
			if(o_distance != MAX_DISTANCE)
			begin
				o_distance <= o_distance+1000;
			end
		end
	end
end

endmodule
