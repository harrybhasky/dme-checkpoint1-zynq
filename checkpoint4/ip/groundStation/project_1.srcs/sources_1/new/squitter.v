//squitter rate 2700 pps
module squitterGen #(parameter pulseWidth=350,pulsePairDelay=250,squitterDelay=18518)(
input		   i_clk_50,
output  reg    o_pulse,
output  reg    o_pulse_valid
);


localparam IDLE        = 'd0,
		   sendPulse1  = 'd1,
		   sendDelay   = 'd2,
		   sendPulse2  = 'd3;

wire sendReply = 0;
reg [1:0] replyState = IDLE;
integer counter = squitterDelay;
integer replyCounter;


always @(posedge i_clk_50)
begin
	if(counter != 0)
		counter <= counter - 1;
	else
		counter <= squitterDelay;
end

assign sendReply = (counter == 0);


always @(posedge i_clk_50)
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
				replyState <= IDLE;
			end		
		end
	endcase
end

endmodule
