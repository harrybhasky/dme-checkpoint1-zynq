module pulseMux (
input          i_clk,
input		   i_stid_valid,
input          i_stdid_pulse,
input		   i_reply_valid,
input          i_reply_pulse,
input          i_squitter_valid,
input          i_squitter_pulse,
output   reg   o_gs_pulse
);

localparam stid  = 'd0,
           rply  = 'd1,
		   sptr  = 'd2;

localparam IDLE 	 = 'd0,
           SENDPulse = 'd1;		  
reg state=IDLE;
reg [1:0] src;

always @(*)
begin
    if(src == stid)
        o_gs_pulse <= i_stdid_pulse;
    else if(src == rply)
        o_gs_pulse <= i_reply_pulse;
    else if(src == sptr)
        o_gs_pulse <= i_squitter_pulse;
    else
        o_gs_pulse <= 0;
end

always @(posedge i_clk)
begin
	case(state)
		IDLE:begin
			if(i_stid_valid)
			begin	
				src <= stid;
				state <= SENDPulse;
			end
			else if(i_reply_valid)
			begin				
				src <= rply;	
				state <= SENDPulse;		
			end
			else if(i_squitter_valid)
			begin
				src <= sptr;	
				state <= SENDPulse;		
			end
		end
		SENDPulse:begin
			if(~i_stid_valid & ~i_reply_valid & ~i_squitter_valid)
			begin	
				state <= IDLE;
		    end
		end
	endcase
end



endmodule