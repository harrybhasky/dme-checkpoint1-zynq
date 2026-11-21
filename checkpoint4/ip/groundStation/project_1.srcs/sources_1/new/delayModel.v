`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/01/2026 03:50:00 PM
// Design Name: 
// Module Name: delayModel
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


module delayModel #(parameter pulseMaxWidth=1000,pulsePairMaxDelay=2000,countPerKM=334)(
input         i_clk,
input         i_in_pulse,
output        o_output_pulse,
input  [19:0] i_dist_m,

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
		   sendPulse2  = 'd3;

reg sendReply = 0;
reg [2:0] state = IDLE;
reg [1:0] replyState = IDLE;
integer counter;
reg dme_gs_fifo_wr_en = 0;
reg dme_gs_fifo_rst = 0;
integer pulseDuration = 0;
reg bypassFifo = 0;
reg [19:0] prev_dist;
reg restart;


always @(posedge i_clk)
begin
	prev_dist <= i_dist_m;
	if(i_dist_m != prev_dist)
		restart <= 1;
	else
		restart <= 0;
end

always @(posedge i_clk or posedge restart)
begin
    if(restart)
    begin
        state <= IDLE;
        dme_gs_fifo_rst <= 1'b1;
        dme_gs_fifo_wr_en <= 1'b0; 
        bypassFifo <= 0;
        sendReply <= 0;
        o_pulse_width_err <= 0;
        o_pulse_delay_err <= 1'b0;
    end
    else
    begin
	case(state)
		IDLE:begin
			sendReply <= 0;
		    dme_gs_fifo_rst <= 1'b1;
			bypassFifo <= 0;
		    if(i_dist_m <= 750000)          //If distance is too low (<20 km), we can continuously store the input data in 
		    begin                           //buffer and confinuously read from there. Fifo depth is enough to 
		        dme_gs_fifo_wr_en <= 1'b1;  //buffer the entire data.
		        sendReply <= 1'b1;
		        dme_gs_fifo_rst <= 1'b0;
		        bypassFifo <= 1;
		        o_pulse_width_err <= 1'b0;
				o_pulse_delay_err <= 1'b0;
		    end	
			else if(i_in_pulse) //wait for pulse to become high
			begin
				state <= checkPulse1;
				counter <= 0;
				dme_gs_fifo_wr_en <= 1'b1;
				dme_gs_fifo_rst <= 1'b0;
				o_pulse_width_err <= 1'b0;
				o_pulse_delay_err <= 1'b0;
			end
		end
		checkPulse1:begin
			if(i_in_pulse)
			begin
			    pulseDuration <= pulseDuration + 1;
				if(counter != pulseMaxWidth)
					counter <= counter+1;
			end
			else
			begin
				if(counter < pulseMaxWidth) //valid pulse
				begin
					state <= checkDelay;
					counter <= 0;
				end
				else  //pulse is too wide to retransmit
				begin
					state <= IDLE;
					dme_gs_fifo_rst <= 1'b1;
				    dme_gs_fifo_wr_en <= 1'b0;
				    pulseDuration <= 0;
				    o_pulse_width_err <= 1;
			    end
			end
		end
		checkDelay:begin
			if(~i_in_pulse)
			begin
			    pulseDuration <= pulseDuration + 1;
				if(counter != pulsePairMaxDelay)
					counter <= counter+1;
			end
			else
			begin
				if(counter < pulsePairMaxDelay) //valid pulse
				begin
					state <= checkPulse2;
					counter <= 0;
				end
				else  //too much inter pulse delay to transmit
				begin
					state <= IDLE;
					dme_gs_fifo_rst <= 1'b1;
					dme_gs_fifo_wr_en <= 1'b0;
					pulseDuration <= 0;
					o_pulse_delay_err <= 1'b1;
			    end
			end	
	
		end
		checkPulse2:begin
			if(i_in_pulse)
			begin
			    pulseDuration <= pulseDuration + 1;
				if(counter != pulseMaxWidth)
					counter <= counter+1;
			end
			else
			begin	
				if(counter < pulseMaxWidth) 
				begin
					state <= prepReply;
                    dme_gs_fifo_wr_en <= 1'b0;
				end
				else
				begin
					dme_gs_fifo_rst <= 1'b1;
					dme_gs_fifo_wr_en <= 1'b0;
					pulseDuration <= 0;
					o_pulse_width_err <= 1'b1;
					state <= IDLE;
			    end
			end
		end		
		prepReply:begin
			sendReply <= 1;
			if(dme_gs_fifo_empty)
			begin
			     state <=  IDLE;
			     sendReply <= 0;
			     pulseDuration <= 0;
			     dme_gs_fifo_rst <= 1'b1;
			end
		end
	endcase
	end
end

integer delayCounter;
reg  sendReply_d;
assign dme_gs_fifo_rd_en = (sendReply_d & (delayCounter==0));

always @(posedge i_clk)
begin
    sendReply_d <= sendReply;
end

always @(posedge i_clk)
begin
    if(sendReply & ~sendReply_d)
        if(bypassFifo)
            delayCounter <= (i_dist_m*countPerKM*33)/32768;//33/32768 ~ 1/1000
        else
            delayCounter <= ((i_dist_m*countPerKM*33)/32768)-pulseDuration;
    else if(delayCounter != 0)
        delayCounter <= delayCounter-1;
end
        


fifo_generator_0 dme_gs_fifo (
  .clk(i_clk),      // input wire clk
  .srst(dme_gs_fifo_rst),    // input wire srst
  .din(i_in_pulse),      // input wire [0 : 0] din
  .wr_en(dme_gs_fifo_wr_en),  // input wire wr_en
  .rd_en(dme_gs_fifo_rd_en),  // input wire rd_en
  .dout(o_output_pulse),    // output wire [0 : 0] dout
  .full(),    // output wire full
  .empty(dme_gs_fifo_empty)  // output wire empty
);

endmodule
