`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 24.04.2026 18:30:25
// Design Name: 
// Module Name: morseGenerator
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

//stationIDDealy = (30*clockFreq*1000000)
module stationIDGen #(parameter clockFreq=40, dotPeriod = 100, ppRate = 1350, stationIDDealy = (30*clockFreq*1000000), num_dot_pp = (dotPeriod*ppRate/1000), pp_delay_count = (clockFreq*1000000/ppRate))( 
input         i_clk,
input  [31:0] i_station,//assumes 8 bits/alphabet max 4 alphabet. input in string
input  [2:0]  i_station_len,//number of alphabets in station code
input         i_station_valid,//make high to send station code
output  reg   o_tx_done,
output        o_pulse,
output  reg   o_sid_valid
);


reg  pg_en;
reg  code_done;
integer num_pp;
reg code_valid;

reg [2:0]  statLen;
reg [4:0]  codeLen;

integer counter=0; //counter to generate pulse pair delay
reg [63:0] stationIDDelayCounter=0; //Counter to make sure station ID is sent once every 30 seconds
wire sendStationID; //Flag becomes high once every 30 seconds to send ID


localparam IDLE      = 'd0,
           GenPulse  = 'd1,
           DELAY     = 'd2,
           getCHAR   = 'd1,
           getCode   = 'd2,
           SendCode  = 'd3,
           WAIT      = 'd4,
		   sendSpace = 'd5;
           
reg [1:0] state=IDLE;    

reg [16:0] morse_rom [0:25]; //memory to store morse code for alphabets
reg [4:0]  morse_len [0:25]; //memory to store number of symbols in each character

initial begin
    morse_rom[0] = 17'b00000000000011101; morse_len[ 0] = 5;  // A  .-
    morse_rom[1] = 17'b00000000101010111; morse_len[ 1] = 9;  // B  -...
    morse_rom[2] = 17'b00000010111010111; morse_len[ 2] = 11; // C  -.-.
    morse_rom[3] = 17'b00000000001010111; morse_len[ 3] = 7;  // D  -..
    morse_rom[4] = 17'b00000000000000001; morse_len[ 4] = 1;  // E  .
    morse_rom[5] = 17'b00000000101110101; morse_len[ 5] = 9;  // F  ..-.
    morse_rom[6] = 17'b00000000101110111; morse_len[ 6] = 9;  // G  --.
    morse_rom[7] = 17'b00000000001010101; morse_len[ 7] = 7;  // H  ....
    morse_rom[8] = 17'b00000000000000101; morse_len[ 8] = 3;  // I  ..
    morse_rom[9] = 17'b00000001110111011; morse_len[ 9] = 13; // J  .---
    morse_rom[10] = 17'b00000000111010111; morse_len[10] = 9;  // K  -.-
    morse_rom[11] = 17'b00000000101011101; morse_len[11] = 9;  // L  .-..
    morse_rom[12] = 17'b00000000001110111; morse_len[12] = 7;  // M  --
    morse_rom[13] = 17'b00000000000010111; morse_len[13] = 5;  // N  -.
    morse_rom[14] = 17'b00000111011101110; morse_len[14] = 15; // O  ---
    morse_rom[15] = 17'b00000010111011101; morse_len[15] = 11; // P  .--.
    morse_rom[16] = 17'b10111010111011101; morse_len[16] = 17; // Q  --.-
    morse_rom[17] = 17'b00000000001011101; morse_len[17] = 7;  // R  .-.
    morse_rom[18] = 17'b00000000000010101; morse_len[18] = 5;  // S  ...
    morse_rom[19] = 17'b00000000000000111; morse_len[19] = 3;  // T  -
    morse_rom[20] = 17'b00000000001110101; morse_len[20] = 7;  // U  ..-
    morse_rom[21] = 17'b00000000111010101; morse_len[21] = 9;  // V  ...-
    morse_rom[22] = 17'b00000000111011101; morse_len[22] = 9;  // W  .--
    morse_rom[23] = 17'b00000011101010111; morse_len[23] = 11; // X  -..-
    morse_rom[24] = 17'b00001110111010111; morse_len[24] = 13; // Y  -.--
    morse_rom[25] = 17'b00000010101110111; morse_len[25] = 11; // Z  --..
end    

integer i=0;
integer j=0;
reg [4:0] char;
reg [2:0] main_state = IDLE;
reg [2:0] prevState;
reg code;
reg [2:0] spaceCount = 0;

//This counter generates 30 second delay to send station ID periodically
always @(posedge i_clk)
begin
    if(stationIDDelayCounter != stationIDDealy-1)
        stationIDDelayCounter <= stationIDDelayCounter+1;
    else
        stationIDDelayCounter <= 0;
end

//This flag triggers once every 30 seconds to send the station ID
assign sendStationID = (stationIDDelayCounter==0);

//The main FSM
//It extracts one character from station ID, fetches its symbols from memory
//and controls the lower state machine to control pulse pair generator
always @(posedge i_clk)
begin
    case(main_state)
	   IDLE:begin
	       o_tx_done <= 0;
	       o_sid_valid <= 0;
	       if(i_station_valid & sendStationID) //send station ID once every 30 seconds if the IP is enabled
	       begin
	           statLen     <= i_station_len;//latch the station ID length
	           main_state  <= getCHAR;      //go to character extraction
	           o_sid_valid <= 1'b1;
	       end
	   end
	   getCHAR:begin
	       if(statLen != 0)
	       begin
	           char <= i_station[(statLen-1)*8+:8]-"A"; //Get one character from input. Eache character is 8 bits wide
	           statLen <= statLen-1;                //Decrement num of characters to send
	           main_state <= getCode;               //Go to extract symbols
	       end
	       else
	       begin
	           main_state <= sendSpace;            //Once all characters are sent, transmit inter word delay (7 dot duration)
	           o_tx_done <= 1'b1;                  //Indicate station ID is transmitted
	           spaceCount <= 7;
	       end
	   end
	   getCode:begin
	       codeLen <= morse_len[char];             //Get the character length (num of symbols/bits)
	       main_state <= SendCode;                 //Transmit the symbol
	       j <= 0;
	   end
	   SendCode:begin
	       if(codeLen != 0)
	       begin
	           code_valid <= 1'b1;                //Control signal to low-level FSM to transmit a symbol
	           codeLen <= codeLen-1;	          //Decrement code length
	           main_state <= WAIT;                //Wait until the low level FSM transmits the symbol
			   prevState <= SendCode;             //To come back to this state after the wait
	           if(morse_rom[char][j] == 1)        //If 1 transmit pulse pair for ~100ms, else keep silent for ~100ms
	           begin
                   code <= 1;                     //To lower FSM to indicate whether 1 to be transmitted (pulse pair present) or 0 (pulse pair absent)
	           end
	           else
	           begin
                   code <= 0;
	           end
	           j <= j+1;                         //Point to next symbol
	       end
	       else
	       begin
	           main_state <= sendSpace;         //If a character is transmitted, wait for 300 ms (duration of 3 dots)
			   spaceCount <= 3;
	       end
	   end
	   WAIT:begin
	       if(code_done) //Wait until the lower FSM sends pulses
	       begin
	           main_state <= prevState;
	           code_valid <= 1'b0;
	       end
	   end
	   sendSpace:begin 
		    if(spaceCount == 0)
		    begin
		        if(o_tx_done)
		        begin
		            main_state <= IDLE;
		        end
		        else
				    main_state <= getCHAR;
		    end
			else
			begin
			    spaceCount <= spaceCount-1;
				main_state <= WAIT;
				code_valid <= 1'b1; //For dummy 1 symbol delay
				code <= 0;
				prevState <= sendSpace;
		    end
	   end
    endcase
end   
 
//Lower level FSM to control the pulse pair generator
//Depending on higher level FSM, it either enables pulse pair generator for the duration of a symbol
//or just waits for the duration of a symbol           
always @(posedge i_clk)
begin
    case(state)
	   IDLE:begin
	       code_done <= 1'b0;
	       if(code_valid)
	       begin
	           num_pp <= num_dot_pp;
	           state <= GenPulse;
	       end
	   end
	   GenPulse:begin
	       if(num_pp != 0)
	       begin
	           pg_en <= code; //either generate pulse pair or just generate delay
	           state <= DELAY;
	           num_pp <= num_pp-1;
	           counter <= pp_delay_count;
	       end
	       else
	       begin
	           code_done <= 1'b1;
	           state <= IDLE;
	       end
	   end
	   DELAY:begin
	       pg_en <= 1'b0;
	       if(counter != 0)
	       begin
	           counter <= counter-1;
	       end
	       else
	       begin
	           state <= GenPulse;
	       end
	   end
    endcase
end

//Pulse pair generator
pulseGenerator #(.clockFreq(clockFreq),.pulseWidth(3.5),.pulseSpace(12))pg
(
	.i_clk(i_clk), //40MHz input clock
	.i_en(pg_en),     //Enable pulse generation
	.o_pulse(o_pulse)
);



endmodule
