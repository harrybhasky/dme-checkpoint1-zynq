module demodulator #(parameter thresholdH = 200, thresholdL=100)(
	input		    i_clk,    // input clock
	input   [11:0]	i_data,     //Enable pulse generation
	output   reg    o_pulse
);

reg [11:0] rectData;
reg [11:0] data=0;
integer sum = 0;


always @(posedge i_clk)
begin
	if($signed(i_data) < 0)
		rectData = -1*i_data;
	else
		rectData <= i_data;
end

always @(posedge i_clk)
begin
	if(rectData >= data) //to avoid x in data
	begin
		data <= rectData;
	end
	else
		if(data > 10)
			data <= data-10;
		else
			data <= 0;
end

always @(posedge i_clk) //We need hysteresis since signal will have ripples
begin
	if(data >= thresholdH)
		o_pulse <= 1'b1;
	else if(data <= thresholdL)
		o_pulse <= 1'b0;
end

endmodule