`timescale 1ns/1ps

// Final project programmable-logic system: the aircraft DME, the ground
// station control registers, and the course ground station IP (unmodified),
// connected directly in the same FPGA (no ADC or DAC).
//
//   PS --AXI (ac_*)--> dme_aircraft_axi4lite --tx_sample--> groundStation
//                              ^                                 |
//                              +-----------rx_sample------------+
//   PS --AXI (gsc_*)-> dme_gs_ctrl_axi4lite --gs_*----> groundStation inputs
//
// vivado/build_project.tcl generates the top level (system_top.v), which
// connects this module to the Zynq block design's two AXI4-Lite master
// ports: aircraft at 0x43C00000, ground station control at 0x43C10000.
module dme_system (
    input  logic        clk,      // FCLK_CLK0, 100 MHz
    input  logic        rstn,     // peripheral_aresetn

    // Aircraft DME, AXI4-Lite slave
    input  logic [31:0] ac_awaddr,
    input  logic        ac_awvalid,
    output logic        ac_awready,
    input  logic [31:0] ac_wdata,
    input  logic [3:0]  ac_wstrb,
    input  logic        ac_wvalid,
    output logic        ac_wready,
    output logic [1:0]  ac_bresp,
    output logic        ac_bvalid,
    input  logic        ac_bready,
    input  logic [31:0] ac_araddr,
    input  logic        ac_arvalid,
    output logic        ac_arready,
    output logic [31:0] ac_rdata,
    output logic [1:0]  ac_rresp,
    output logic        ac_rvalid,
    input  logic        ac_rready,

    // Ground station control, AXI4-Lite slave
    input  logic [31:0] gsc_awaddr,
    input  logic        gsc_awvalid,
    output logic        gsc_awready,
    input  logic [31:0] gsc_wdata,
    input  logic [3:0]  gsc_wstrb,
    input  logic        gsc_wvalid,
    output logic        gsc_wready,
    output logic [1:0]  gsc_bresp,
    output logic        gsc_bvalid,
    input  logic        gsc_bready,
    input  logic [31:0] gsc_araddr,
    input  logic        gsc_arvalid,
    output logic        gsc_arready,
    output logic [31:0] gsc_rdata,
    output logic [1:0]  gsc_rresp,
    output logic        gsc_rvalid,
    input  logic        gsc_rready
);
    // Aircraft <-> station signals. mark_debug lets them be added to an ILA
    // with Tools > Set Up Debug after synthesis.
    (* mark_debug = "true" *) logic signed [11:0] tx_sample;
    (* mark_debug = "true" *) logic               tx_pulse;
    (* mark_debug = "true" *) logic               tx_start;
    (* mark_debug = "true" *) logic [11:0]        gs_out;
    (* mark_debug = "true" *) logic               gs_pulse;
    (* mark_debug = "true" *) logic               rx_pulse;
    (* mark_debug = "true" *) logic               reply_detected;
    logic [15:0] rx_envelope;

    logic [19:0] gs_distance, gs_distance_now, gs_pulse_rate;
    logic [7:0]  gs_speed;
    logic [6:0]  gs_efficiency;
    logic        gs_direction, gs_var_distance, gs_squitter_en, gs_jitter_en;
    logic        gs_ident, gs_pulse_en, gs_pw_error, gs_pd_error;

    dme_aircraft_axi4lite aircraft (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rstn),
        .s_axi_awaddr(ac_awaddr[6:0]),
        .s_axi_awvalid(ac_awvalid),
        .s_axi_awready(ac_awready),
        .s_axi_wdata(ac_wdata),
        .s_axi_wstrb(ac_wstrb),
        .s_axi_wvalid(ac_wvalid),
        .s_axi_wready(ac_wready),
        .s_axi_bresp(ac_bresp),
        .s_axi_bvalid(ac_bvalid),
        .s_axi_bready(ac_bready),
        .s_axi_araddr(ac_araddr[6:0]),
        .s_axi_arvalid(ac_arvalid),
        .s_axi_arready(ac_arready),
        .s_axi_rdata(ac_rdata),
        .s_axi_rresp(ac_rresp),
        .s_axi_rvalid(ac_rvalid),
        .s_axi_rready(ac_rready),
        .tx_sample(tx_sample),
        .tx_pulse(tx_pulse),
        .rx_sample(gs_out),
        .tx_start(tx_start),
        .rx_envelope(rx_envelope),
        .rx_pulse(rx_pulse),
        .reply_detected(reply_detected),
        .irq()
    );

    dme_gs_ctrl_axi4lite gs_ctrl (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rstn),
        .s_axi_awaddr(gsc_awaddr[5:0]),
        .s_axi_awvalid(gsc_awvalid),
        .s_axi_awready(gsc_awready),
        .s_axi_wdata(gsc_wdata),
        .s_axi_wstrb(gsc_wstrb),
        .s_axi_wvalid(gsc_wvalid),
        .s_axi_wready(gsc_wready),
        .s_axi_bresp(gsc_bresp),
        .s_axi_bvalid(gsc_bvalid),
        .s_axi_bready(gsc_bready),
        .s_axi_araddr(gsc_araddr[5:0]),
        .s_axi_arvalid(gsc_arvalid),
        .s_axi_arready(gsc_arready),
        .s_axi_rdata(gsc_rdata),
        .s_axi_rresp(gsc_rresp),
        .s_axi_rvalid(gsc_rvalid),
        .s_axi_rready(gsc_rready),
        .gs_distance(gs_distance),
        .gs_speed(gs_speed),
        .gs_direction(gs_direction),
        .gs_var_distance(gs_var_distance),
        .gs_efficiency(gs_efficiency),
        .gs_squitter_en(gs_squitter_en),
        .gs_pulse_rate(gs_pulse_rate),
        .gs_jitter_en(gs_jitter_en),
        .gs_ident(gs_ident),
        .gs_pulse_en(gs_pulse_en),
        .gs_distance_now(gs_distance_now),
        .gs_pulse_width_error(gs_pw_error),
        .gs_pulse_delay_error(gs_pd_error)
    );

    // Course ground station, mod = 0: it demodulates our 10 MHz samples.
    groundStation #(.mod(0)) gs (
        .i_clk_100(clk),
        .i_dme_data(tx_sample),
        .i_pulse_en(gs_pulse_en),
        .i_efficiency(gs_efficiency),
        .i_ident(gs_ident),
        .i_distance(gs_distance),
        .o_distance(gs_distance_now),
        .i_speed(gs_speed),
        .i_pulse_rate(gs_pulse_rate),
        .i_direction(gs_direction),
        .i_var_distance(gs_var_distance),
        .i_squitter_en(gs_squitter_en),
        .i_jitter_en(gs_jitter_en),
        .i_dme_pulse(tx_pulse),
        .o_gs_pulse(gs_pulse),
        .o_gs_out(gs_out),
        .o_pulse_width_error(gs_pw_error),
        .o_pulse_delay_error(gs_pd_error)
    );
endmodule
