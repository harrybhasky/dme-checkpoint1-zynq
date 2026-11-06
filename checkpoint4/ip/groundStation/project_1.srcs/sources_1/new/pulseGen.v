module pulseGenerator #(parameter clockFreq=40,pulseWidth=3.5,pulseSpace=12,pulseWidthCount=clockFreq*pulseWidth, pulseSpaceCount=(pulseSpace*clockFreq-pulseWidthCount))
(
	input		i_clk,    // input clock
	input		i_en,     //Enable pulse generation
	output reg  o_pulse
);



integer counter = 0;

localparam IDLE = 'd0,
           HIGH1 = 'd1,
           LOW   = 'd2,
           HIGH2 = 'd3;
           
reg [2:0] state=IDLE;
reg en_p;

initial
begin
	o_pulse = 0;
end

always @(posedge i_clk)
begin
    en_p <= i_en;
end

always @(posedge i_clk)
begin
case(state)
	IDLE:begin
		if(i_en&~en_p) //when enabled, sends a single pulse
		begin
			counter <= pulseWidthCount;
			o_pulse <= 1'b1; //Make pulse high
			state   <= HIGH1;
		end
	end
	HIGH1:begin
		if(counter != 1)
		begin
			counter <= counter-1;
		end
		else
		begin
			counter <= pulseSpaceCount;
			o_pulse <= 1'b0; //Make pulse high
			state   <= LOW;
		end
	end
	LOW:begin
		if(counter != 1)
		begin
			counter <= counter-1;
		end
		else
		begin
			counter <= pulseWidthCount;
			o_pulse <= 1'b1; //Make pulse high
			state   <= HIGH2;
		end
	end
	HIGH2:begin
		if(counter != 1)
		begin
			counter <= counter-1;
		end
		else
		begin
			o_pulse <= 1'b0; //Make pulse high
			state   <= IDLE;
		end
	end	
endcase
end



endmodule