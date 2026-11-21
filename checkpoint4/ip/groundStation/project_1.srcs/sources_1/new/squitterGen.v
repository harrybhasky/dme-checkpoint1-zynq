//squitter rate 2700 pps
module squitterGen #(parameter pulseWidth=700,pulsePairDelay=500)(
input		   i_clk, //100MHz clock
input  [27:0]  squitterDelay,
input		   i_en,
output  reg    o_pulse,
output  reg    o_pulse_valid
);

localparam IDLE        = 'd0,
		   sendPulse1  = 'd1,
		   sendDelay   = 'd2,
		   sendPulse2  = 'd3,
		   DELAY       = 'd4;

wire sendReply;
reg [2:0] replyState = IDLE;
integer counter = 100000;
integer replyCounter;


always @(posedge i_clk)
begin
	if(counter != 0)
		counter <= counter - 1;
	else
		counter <= squitterDelay;
end

assign sendReply = (counter == 0) & i_en;


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
			if(replyCounter != pulsePairDelay)
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
