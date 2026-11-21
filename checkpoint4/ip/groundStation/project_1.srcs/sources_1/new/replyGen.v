module replyGen #(parameter pulseWidth=700,pulsePairDelay=500,pulseMinWidth=650,pulseMaxWidth=750,pulsePairMinDelay=450,pulsePairMaxDelay=550,fixedDelay=5000)(
input		   i_clk,
input		   i_pulse,
input          i_mode, //0-x,1-y
input  [27:0]  squitterDelay,
input		   i_jitter_en,
output  reg    o_pulse,
output  reg    o_pulse_valid,

output reg    o_pulse_width_err,
output reg    o_pulse_delay_err
);


localparam IDLE        = 'd0,
           checkPulse1 = 'd1,
		   checkDelay  = 'd2,
		   checkPulse2 = 'd3,
		   prepReply   = 'd4,
		   sendPulse1  = 'd1,
		   sendDelay   = 'd2,
		   sendPulse2  = 'd3,
		   delayPulse  = 'd4,
		   DELAY       = 'd5;

reg sendReply = 0;
reg [2:0] state = IDLE;
reg [2:0] replyState = IDLE;
integer counter;
integer replyCounter;
integer totalCounter;
reg [7:0] jitter = 'h1; //lfsr to generate jitter between 1 to 255


always @(posedge i_clk) 
begin
	if(i_jitter_en)
		jitter <= {jitter[6:0],(jitter[7]^jitter[5]^jitter[4]^jitter[3])};
end


always @(posedge i_clk)
begin
	case(state)
		IDLE:begin
			sendReply <= 0;
			if(i_pulse) //wait for pulse to become high
			begin
				state <= checkPulse1;
				counter <= 0;
				totalCounter <= 0;
				o_pulse_width_err <= 1'b0;
				o_pulse_delay_err <= 1'b0;
			end
		end
		checkPulse1:begin
			if(i_pulse)
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
				begin
					state <= IDLE;
					o_pulse_width_err <= 1'b1;
			    end
			end
			totalCounter <= totalCounter+1;
		end
		checkDelay:begin
			if(~i_pulse)
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
				begin
					state <= IDLE;
					o_pulse_delay_err <= 1'b1;
				end
			end	
			totalCounter <= totalCounter+1;		
		end
		checkPulse2:begin
			if(i_pulse)
			begin
				if(counter != pulseMaxWidth)
					counter <= counter+1;
			end
			else
			begin	
				if((counter >= pulseMinWidth) & (counter < pulseMaxWidth)) //valid pulse
				begin
					state <= prepReply;
					counter <= 0;
				end
				else
				begin
					state <= IDLE;
					o_pulse_width_err <= 1'b1;
			    end
			end
			totalCounter <= totalCounter+1;
		end		
		prepReply:begin
			if(totalCounter < fixedDelay+jitter)
				totalCounter <= totalCounter+1;
			else
			begin
				state <= IDLE;
				sendReply <= 1;
			end
		end
	endcase
end


always @(posedge i_clk)
begin
	case(replyState)
		IDLE:begin
		    o_pulse_valid <= 1'b0;
			o_pulse <= 1'b0;
			if(sendReply)
			begin
				replyState <= sendPulse1;
				replyCounter <= 0;
			end
		end
		sendPulse1:begin
			o_pulse <= 1'b1;
			o_pulse_valid <= 1'b1;
			if(replyCounter != pulseWidth)
				replyCounter <= replyCounter+1;
			else
			begin
				replyState <= sendDelay;
				replyCounter <= 0;
			end		
		end
		sendDelay:begin
			o_pulse <= 0;
			if(replyCounter != pulsePairDelay)
				replyCounter <= replyCounter+1;
			else
			begin
				replyState <= sendPulse2;
				replyCounter <= 0;
			end
		end
		sendPulse2:begin
			o_pulse <= 1'b1;
			if(replyCounter != pulseWidth)
				replyCounter <= replyCounter+1;
			else
			begin
				replyState <= DELAY;
				replyCounter <= 0;
			end		
		end
		DELAY:begin
			o_pulse <= 1'b0;
			if(replyCounter < squitterDelay)
				replyCounter <= replyCounter+1;
			else
			begin
				replyState <= IDLE;
				replyCounter <= 0;
			end	
		end
	endcase
end

endmodule
