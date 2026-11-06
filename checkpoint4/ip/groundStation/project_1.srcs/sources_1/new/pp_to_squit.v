module pp_to_squit(
input             i_clk,
input			  i_squitter_en,
input      [19:0] i_pulse_rate,
output reg [27:0] squitDelay 
);


wire [47:0] divideOut;

div_gen_0 findPulseRate (
  .aclk(i_clk),                                     
  .s_axis_divisor_tvalid(1),    
  .s_axis_divisor_tdata(i_pulse_rate),    
  .s_axis_dividend_tvalid(1), 
  .s_axis_dividend_tdata(100000000),   
  .m_axis_dout_tvalid(squitDelayValid),         
  .m_axis_dout_tdata(divideOut)  
);

always @(posedge i_clk)
begin
	if(~i_squitter_en)
		squitDelay <= 0;
	else if(squitDelayValid)
		squitDelay <= divideOut[43:16];
end


endmodule