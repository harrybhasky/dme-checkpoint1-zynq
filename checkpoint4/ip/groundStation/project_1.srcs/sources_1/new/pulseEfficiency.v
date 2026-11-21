module pulseEfficiency #(parameter pulseMinWidth=550,pulseMaxWidth=750,pulsePairMinDelay=450,pulsePairMaxDelay=650)(
input	      i_clk, //100MHz clock
input [6:0]   i_efficiency,
input	      i_data,
output        o_data
);

localparam IDLE        = 'd0,
           checkPulse1 = 'd1,
		   checkDelay  = 'd2,
		   checkPulse2 = 'd3;

reg [15:0] lfsr = 16'hACE1;
wire [15:0] threshold;
integer counter = 0;
reg [1:0] state = IDLE;
reg enLFSR;

assign threshold = i_efficiency*655;
assign o_data = (lfsr < threshold) ? i_data : 0;

always @(posedge i_clk)
begin
	if(enLFSR)
		lfsr <= {lfsr[14:0],lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
end


always @(posedge i_clk)
begin
	case(state)
		IDLE:begin
			enLFSR <= 0;
			if(i_data) //wait for pulse to become high
			begin
				state <= checkPulse1;
				counter <= 0;
			end
		end
		checkPulse1:begin
			if(i_data)
			begin
				if(counter != pulseMaxWidth)
					counter <= counter+1;
			end
			else
			begin
				if((counter >= pulseMinWidth) & (counter < pulseMaxWidth)) //valid pulse
				begin
					state <= checkDelay;
					counter <= 0;
				end
				else  //wrong width
					state <= IDLE;
			end
		end
		checkDelay:begin
			if(~i_data)
			begin
				if(counter != pulsePairMaxDelay)
					counter <= counter+1;
			end
			else
			begin
				if((counter >= pulsePairMinDelay) & (counter < pulsePairMaxDelay)) //valid pulse
				begin
					state <= checkPulse2;
					counter <= 0;
				end
				else  //wrong delay
					state <= IDLE;
			end		
		end
		checkPulse2:begin
			if(i_data)
			begin
				if(counter != pulseMaxWidth)
					counter <= counter+1;
			end
			else
			begin	
				if((counter >= pulseMinWidth) & (counter < pulseMaxWidth)) //valid pulse
				begin
					state <= IDLE;
					enLFSR <= 1;
				end
			end
		end		
	endcase
end


endmodule