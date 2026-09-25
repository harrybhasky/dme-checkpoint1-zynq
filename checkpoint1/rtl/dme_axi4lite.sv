`timescale 1ns/1ps

module dme_axi4lite #(
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned CARRIER_HZ = 1_000_000,
    parameter int unsigned PULSE_WIDTH_US = 50,
    parameter int unsigned INTER_PULSE_DELAY_US = 350,
    parameter int unsigned DEFAULT_PAIR_RATE_HZ = 30
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
    output logic        pulse_pair,
    output logic        carrier,
    output logic        modulated_out
);
    localparam logic [31:0] MIN_PERIOD_US =
        PULSE_WIDTH_US + INTER_PULSE_DELAY_US + PULSE_WIDTH_US;

    logic        enable_reg;
    logic        carrier_enable_reg;
    logic [31:0] period_reg;
    logic [31:0] elapsed_us;
    logic        aw_pending;
    logic [5:0]  awaddr_reg;
    logic        w_pending;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    dme_pulse_pair_modulator #(
        .CLK_HZ(CLK_HZ),
        .CARRIER_HZ(CARRIER_HZ),
        .PULSE_WIDTH_US(PULSE_WIDTH_US),
        .INTER_PULSE_DELAY_US(INTER_PULSE_DELAY_US),
        .DEFAULT_PAIR_RATE_HZ(DEFAULT_PAIR_RATE_HZ)
    ) core (
        .clk(s_axi_aclk),
        .rst_n(s_axi_aresetn),
        .enable(enable_reg),
        .carrier_enable(carrier_enable_reg),
        .pair_period_us(period_reg),
        .elapsed_us,
        .pulse_pair,
        .carrier,
        .modulated_out
    );

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            enable_reg        <= 1'b0;
            carrier_enable_reg <= 1'b1;
            period_reg        <= (DEFAULT_PAIR_RATE_HZ == 0) ? 32'd33333 :
                                 (1_000_000 + DEFAULT_PAIR_RATE_HZ / 2) /
                                 DEFAULT_PAIR_RATE_HZ;
            aw_pending        <= 1'b0;
            w_pending         <= 1'b0;
            awaddr_reg        <= 6'd0;
            wdata_reg         <= 32'd0;
            wstrb_reg         <= 4'd0;
            s_axi_bvalid      <= 1'b0;
            s_axi_bresp       <= 2'b00;
            s_axi_rvalid      <= 1'b0;
            s_axi_rdata       <= 32'd0;
            s_axi_rresp       <= 2'b00;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_pending <= 1'b1;
                awaddr_reg <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_pending <= 1'b1;
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
            end

            if (aw_pending && w_pending && !s_axi_bvalid) begin
                if (awaddr_reg[5:2] == 4'h0) begin
                    if (wstrb_reg[0]) begin
                        enable_reg         <= wdata_reg[0];
                        carrier_enable_reg <= wdata_reg[1];
                    end
                end else if (awaddr_reg[5:2] == 4'h1 &&
                             wdata_reg >= MIN_PERIOD_US) begin
                    if (wstrb_reg[0]) period_reg[7:0]   <= wdata_reg[7:0];
                    if (wstrb_reg[1]) period_reg[15:8]  <= wdata_reg[15:8];
                    if (wstrb_reg[2]) period_reg[23:16] <= wdata_reg[23:16];
                    if (wstrb_reg[3]) period_reg[31:24] <= wdata_reg[31:24];
                end
                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                case (s_axi_araddr[5:2])
                    4'h0: s_axi_rdata <= {30'd0, carrier_enable_reg, enable_reg};
                    4'h1: s_axi_rdata <= period_reg;
                    4'h2: s_axi_rdata <= {30'd0, (enable_reg && pulse_pair), pulse_pair};
                    4'h3: s_axi_rdata <= elapsed_us;
                    default: begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= 2'b11;
                    end
                endcase
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end
endmodule
