`timescale 1ns/1ps

// Checkpoint 4: AXI4-Lite control for the course ground station IP
// (groundStation). Each output drives the station input of the same name,
// so software can set up every test case without rebuilding the bitstream.
module dme_gs_ctrl_axi4lite #(
    parameter int unsigned DEFAULT_DISTANCE_M = 0,
    parameter int unsigned DEFAULT_EFFICIENCY = 100,
    parameter int unsigned DEFAULT_PULSE_RATE = 2500
) (
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    input  logic [5:0]  s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [5:0]  s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // To groundStation inputs
    output logic [19:0] gs_distance,
    output logic [7:0]  gs_speed,
    output logic        gs_direction,
    output logic        gs_var_distance,
    output logic [6:0]  gs_efficiency,
    output logic        gs_squitter_en,
    output logic [19:0] gs_pulse_rate,
    output logic        gs_jitter_en,
    output logic        gs_ident,
    output logic        gs_pulse_en,
    // From groundStation outputs
    input  logic [19:0] gs_distance_now,
    input  logic        gs_pulse_width_error,
    input  logic        gs_pulse_delay_error
);
    localparam logic [3:0] REG_CONTROL      = 4'h0;
    localparam logic [3:0] REG_DISTANCE     = 4'h1;
    localparam logic [3:0] REG_SPEED        = 4'h2;
    localparam logic [3:0] REG_EFFICIENCY   = 4'h3;
    localparam logic [3:0] REG_PULSE_RATE   = 4'h4;
    localparam logic [3:0] REG_DISTANCE_NOW = 4'h5;
    localparam logic [3:0] REG_ERRORS       = 4'h6;
    localparam logic [3:0] REG_PW_ERR_COUNT = 4'h7;
    localparam logic [3:0] REG_PD_ERR_COUNT = 4'h8;

    logic        aw_pending;
    logic [5:0]  awaddr_reg;
    logic        w_pending;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;
    logic        clear_pulse;
    logic        pw_err_d;
    logic        pd_err_d;
    logic [31:0] pw_err_count;
    logic [31:0] pd_err_count;

    wire write_fire = aw_pending && w_pending && !s_axi_bvalid;
    wire read_fire  = s_axi_arvalid && s_axi_arready;

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    // Count each rising edge of the station's error flags.
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || clear_pulse) begin
            pw_err_d     <= 1'b0;
            pd_err_d     <= 1'b0;
            pw_err_count <= 32'd0;
            pd_err_count <= 32'd0;
        end else begin
            pw_err_d <= gs_pulse_width_error;
            pd_err_d <= gs_pulse_delay_error;
            if (gs_pulse_width_error && !pw_err_d) pw_err_count <= pw_err_count + 1'b1;
            if (gs_pulse_delay_error && !pd_err_d) pd_err_count <= pd_err_count + 1'b1;
        end
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            gs_distance     <= 20'(DEFAULT_DISTANCE_M);
            gs_speed        <= 8'd0;
            gs_direction    <= 1'b0;
            gs_var_distance <= 1'b0;
            gs_efficiency   <= 7'(DEFAULT_EFFICIENCY);
            gs_squitter_en  <= 1'b0;
            gs_pulse_rate   <= 20'(DEFAULT_PULSE_RATE);
            gs_jitter_en    <= 1'b0;
            gs_ident        <= 1'b0;
            gs_pulse_en     <= 1'b1;
            clear_pulse     <= 1'b0;
            aw_pending      <= 1'b0;
            w_pending       <= 1'b0;
            awaddr_reg      <= 6'd0;
            wdata_reg       <= 32'd0;
            wstrb_reg       <= 4'd0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= 32'd0;
            s_axi_rresp     <= 2'b00;
        end else begin
            clear_pulse <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending <= 1'b1;
                awaddr_reg <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending <= 1'b1;
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
            end

            // Registers are written whole (32-bit stores from the driver).
            if (write_fire) begin
                s_axi_bresp <= 2'b00;
                case (awaddr_reg[5:2])
                    REG_CONTROL: begin
                        gs_var_distance <= wdata_reg[0];
                        gs_direction    <= wdata_reg[1];
                        gs_squitter_en  <= wdata_reg[2];
                        gs_jitter_en    <= wdata_reg[3];
                        gs_ident        <= wdata_reg[4];
                        gs_pulse_en     <= wdata_reg[5];
                        if (wdata_reg[31])
                            clear_pulse <= 1'b1;
                    end
                    REG_DISTANCE:   gs_distance   <= wdata_reg[19:0];
                    REG_SPEED:      gs_speed      <= wdata_reg[7:0];
                    REG_EFFICIENCY: gs_efficiency <= (wdata_reg > 32'd100) ? 7'd100 : wdata_reg[6:0];
                    REG_PULSE_RATE: gs_pulse_rate <= wdata_reg[19:0];
                    REG_DISTANCE_NOW, REG_ERRORS, REG_PW_ERR_COUNT,
                    REG_PD_ERR_COUNT: ; // read-only
                    default: s_axi_bresp <= 2'b10;
                endcase
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (read_fire) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                case (s_axi_araddr[5:2])
                    REG_CONTROL:      s_axi_rdata <= {26'd0, gs_pulse_en, gs_ident, gs_jitter_en,
                                                      gs_squitter_en, gs_direction, gs_var_distance};
                    REG_DISTANCE:     s_axi_rdata <= {12'd0, gs_distance};
                    REG_SPEED:        s_axi_rdata <= {24'd0, gs_speed};
                    REG_EFFICIENCY:   s_axi_rdata <= {25'd0, gs_efficiency};
                    REG_PULSE_RATE:   s_axi_rdata <= {12'd0, gs_pulse_rate};
                    REG_DISTANCE_NOW: s_axi_rdata <= {12'd0, gs_distance_now};
                    REG_ERRORS:       s_axi_rdata <= {30'd0, gs_pulse_delay_error, gs_pulse_width_error};
                    REG_PW_ERR_COUNT: s_axi_rdata <= pw_err_count;
                    REG_PD_ERR_COUNT: s_axi_rdata <= pd_err_count;
                    default: begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= 2'b10;
                    end
                endcase
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end
endmodule
