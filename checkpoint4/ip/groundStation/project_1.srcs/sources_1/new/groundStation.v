`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/01/2026 06:38:32 PM
// Design Name: 
// Module Name: groundStation
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


module groundStation #(parameter mod = 0)(
input         i_clk_100,
input  [11:0] i_dme_data,
input		  i_pulse_en,
input  [6:0]  i_efficiency, //pulse reply efficiency
input         i_ident,    //Make high to enable station ID transmit
input  [19:0] i_distance, //Distance to ground station in meters
output [19:0] o_distance,
input  [7:0]  i_speed,
input  [19:0] i_pulse_rate,
input         i_direction,
input		  i_var_distance,
input         i_squitter_en,
input		  i_jitter_en,
input         i_dme_pulse,
output        o_gs_pulse,
output [11:0] o_gs_out,
output        o_pulse_width_error,
output        o_pulse_delay_error
);

wire delay_pulse;
reg dme_pulse;
reg dme_pulse_p;
wire [19:0] distance;
wire dme_pulse_out;
wire r_pw_error;
wire r_pd_error;
wire d_pw_err;
wire d_pd_err;

assign o_distance = distance;
assign o_pulse_width_error = r_pw_error|d_pw_err;
assign o_pulse_delay_error = r_pd_error|d_pd_err;

//double synchronize
always @(posedge i_clk_100)
begin
	if(i_pulse_en)
	begin
		dme_pulse   <= i_dme_pulse;
		dme_pulse_p <= dme_pulse;
	end
	else
		dme_pulse_p <= 0;
end

wire dmodOut;
wire pulseIn;

	
assign pulseIn = (mod == 0) ? dmodOut : dme_pulse_p;

demodulator demod(
	.i_clk(i_clk_100),    // input clock
	.i_data(i_dme_data),     //Enable pulse generation
	.o_pulse(dmodOut)
);

pulseEfficiency pE(
	.i_clk(i_clk_100),
	.i_efficiency(i_efficiency),
	.i_data(pulseIn),
	.o_data(dme_pulse_out)
);


distanceModel distM(
	.i_clk(i_clk_100),
	.i_speed(i_speed),
	.i_en(i_var_distance),
	.i_distance(i_distance),  //distance in meters
	.i_direction(i_direction), //0-towards gs, 1-away gs
	.o_distance(distance)   //distance in meters
);

delayModel dm1(
    .i_clk(i_clk_100),
    .i_in_pulse(dme_pulse_out),
    .o_output_pulse(delay_pulse),
    .i_dist_m(distance),
    .o_pulse_width_err(d_pw_err),
    .o_pulse_delay_err(d_pd_err)
);

wire  [27:0]  squitDelay;

pp_to_squit ppToSquit(
  .i_clk(i_clk_100),
  .i_squitter_en(i_squitter_en),
  .i_pulse_rate(i_pulse_rate),
  .squitDelay(squitDelay) 
);


wire replyPulse;
wire replyPulse_valid;


replyGen rGen(
    .i_clk(i_clk_100),
    .i_pulse(delay_pulse),
	.i_jitter_en(i_jitter_en),
	.squitterDelay(squitDelay),
    .i_mode(0), //0-x,1-y
    .o_pulse(replyPulse),
    .o_pulse_valid(replyPulse_valid),
    .o_pulse_width_err(r_pw_error),
    .o_pulse_delay_err(r_pd_error)
);

wire gs_pulse;

delayModel dm2(
    .i_clk(i_clk_100),
    .i_in_pulse(gs_pulse),
    .o_output_pulse(o_gs_pulse),
    .i_dist_m(distance),
    .o_pulse_width_err(),
    .o_pulse_delay_err()
);

wire std_id_valid;
wire std_pulse;

stationIDGen #(.clockFreq(100)) SID ( 
  .i_clk(i_clk_100),
  .i_station("BLR"),//assumes 5 bits/alphabet max 6 alphabet. first chara from LSB. chara is position in alphabet. Eg: For A-0, for B-1 etc
  .i_station_len(3),//number of alphabets in station code
  .i_station_valid(i_ident),//make high to send station code
  .o_sid_valid(std_id_valid),
  .o_tx_done(),
  .o_pulse(std_pulse)
);


squitterGen SQGen(
  .i_clk(i_clk_100),
  .squitterDelay(squitDelay),
  .i_en(i_squitter_en),
  .o_pulse(squit_pulse),
  .o_pulse_valid(sequit_pulse_valid)
);


pulseMux pMux(
     .i_clk(i_clk_100),
     .i_stid_valid(std_id_valid),
     .i_stdid_pulse(std_pulse),
     .i_reply_valid(replyPulse_valid),
     .i_reply_pulse(replyPulse),
     .i_squitter_valid(sequit_pulse_valid),
     .i_squitter_pulse(squit_pulse),
     .o_gs_pulse(gs_pulse)
);

wire [11:0] pulse;

ppGen ppGen(
 .i_rf_clk(i_clk_100),
 .i_pulsePairEnable(o_gs_pulse),
 .o_pulse(pulse)
);

wire [11:0] m_axis_data_tdata;

dds_compiler_0 carrier (
  .aclk(i_clk_100),                              // input wire aclk
  .m_axis_data_tvalid(),  // output wire m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata)    // output wire [15 : 0] m_axis_data_tdata
);

mixer mix(
    .i_clk(i_clk_100),
    .i_baseband(pulse),
    .i_carrier(m_axis_data_tdata),
    .o_tx_data(o_gs_out)
);



endmodule
