`timescale 1ns / 1ps
// Behavioural simulation models of the four Xilinx IP cores inside the
// course ground station IP (checkpoint4/ip/groundStation). They follow the
// .xci settings of that IP. Only Icarus uses them. Vivado uses the real
// cores packaged with the IP.
//
//   dds_compiler_0   10 MHz cosine, 12-bit, latency 7
//   fifo_generator_0 1-bit standard FIFO, 131072 deep, common clock, srst
//   div_gen_0        28-bit / 12-bit unsigned, integer remainder, latency 30
//   div_gen_1        12-bit / 8-bit unsigned, integer remainder, latency 14

module dds_compiler_0 (
    input  wire        aclk,
    output wire        m_axis_data_tvalid,
    output wire [15:0] m_axis_data_tdata
);
    localparam [31:0] PHASE_INC = 32'h1999999A; // 0.1 cycle/clock = 10 MHz
    localparam integer LATENCY = 7;
    localparam real    TWO_PI = 6.283185307179586;

    reg [31:0] phase = 32'd0;
    reg [11:0] pipe [0:LATENCY-1];
    reg [LATENCY-1:0] valid_pipe = {LATENCY{1'b0}};
    integer i;
    real    c;

    initial
        for (i = 0; i < LATENCY; i = i + 1)
            pipe[i] = 12'd0;

    always @(posedge aclk) begin
        c = 2047.0 * $cos(TWO_PI * phase / 4294967296.0);
        pipe[0] <= (c >= 0.0) ? $rtoi(c + 0.5) : -$rtoi(-c + 0.5);
        for (i = 1; i < LATENCY; i = i + 1)
            pipe[i] <= pipe[i-1];
        valid_pipe <= {valid_pipe[LATENCY-2:0], 1'b1};
        phase <= phase + PHASE_INC;
    end

    assign m_axis_data_tvalid = valid_pipe[LATENCY-1];
    assign m_axis_data_tdata  = {{4{pipe[LATENCY-1][11]}}, pipe[LATENCY-1]};
endmodule

module fifo_generator_0 (
    input  wire clk,
    input  wire srst,
    input  wire din,
    input  wire wr_en,
    input  wire rd_en,
    output reg  dout,
    output wire full,
    output wire empty
);
    localparam integer DEPTH = 131072;

    reg     mem [0:DEPTH-1];
    integer wr_ptr = 0;
    integer rd_ptr = 0;
    integer count  = 0;

    initial dout = 1'b0;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    always @(posedge clk) begin
        if (srst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            dout   <= 1'b0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr] <= din;
                wr_ptr <= (wr_ptr == DEPTH - 1) ? 0 : wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                dout   <= mem[rd_ptr];
                rd_ptr <= (rd_ptr == DEPTH - 1) ? 0 : rd_ptr + 1;
            end
            count <= count + ((wr_en && !full) ? 1 : 0)
                           - ((rd_en && !empty) ? 1 : 0);
        end
    end
endmodule

// div_gen output with "Remainder type: Remainder": tdata = {quotient,
// remainder}, each field padded to a whole number of bytes. The station
// only uses the quotient.
module div_gen_0 (
    input  wire        aclk,
    input  wire        s_axis_divisor_tvalid,
    input  wire [15:0] s_axis_divisor_tdata,
    input  wire        s_axis_dividend_tvalid,
    input  wire [31:0] s_axis_dividend_tdata,
    output wire        m_axis_dout_tvalid,
    output wire [47:0] m_axis_dout_tdata
);
    localparam integer LATENCY = 30;

    reg [47:0] pipe [0:LATENCY-1];
    reg [LATENCY-1:0] valid_pipe = {LATENCY{1'b0}};
    wire [27:0] dividend = s_axis_dividend_tdata[27:0];
    wire [11:0] divisor  = s_axis_divisor_tdata[11:0];
    integer i;

    always @(posedge aclk) begin
        if (divisor == 0)
            pipe[0] <= 48'h0FFF_FFFF_0000;
        else
            pipe[0] <= {4'd0, 28'(dividend / divisor), 4'd0, 12'(dividend % divisor)};
        for (i = 1; i < LATENCY; i = i + 1)
            pipe[i] <= pipe[i-1];
        valid_pipe <= {valid_pipe[LATENCY-2:0],
                       s_axis_divisor_tvalid & s_axis_dividend_tvalid};
    end

    assign m_axis_dout_tvalid = valid_pipe[LATENCY-1];
    assign m_axis_dout_tdata  = pipe[LATENCY-1];
endmodule

module div_gen_1 (
    input  wire        aclk,
    input  wire        s_axis_divisor_tvalid,
    input  wire [7:0]  s_axis_divisor_tdata,
    input  wire        s_axis_dividend_tvalid,
    input  wire [15:0] s_axis_dividend_tdata,
    output wire        m_axis_dout_tvalid,
    output wire [23:0] m_axis_dout_tdata
);
    localparam integer LATENCY = 14;

    reg [23:0] pipe [0:LATENCY-1];
    reg [LATENCY-1:0] valid_pipe = {LATENCY{1'b0}};
    wire [11:0] dividend = s_axis_dividend_tdata[11:0];
    wire [7:0]  divisor  = s_axis_divisor_tdata;
    integer i;

    always @(posedge aclk) begin
        if (divisor == 0)
            pipe[0] <= 24'h0FFF00;
        else
            pipe[0] <= {4'd0, dividend / divisor, 8'(dividend % divisor)};
        for (i = 1; i < LATENCY; i = i + 1)
            pipe[i] <= pipe[i-1];
        valid_pipe <= {valid_pipe[LATENCY-2:0],
                       s_axis_divisor_tvalid & s_axis_dividend_tvalid};
    end

    assign m_axis_dout_tvalid = valid_pipe[LATENCY-1];
    assign m_axis_dout_tdata  = pipe[LATENCY-1];
endmodule
