/////////////////////////////////////////////////////////////////////////////////////////////////
// Command processing module processes commands from UART_wrapper. Uses cmd command from host //
// to read and write to registers, and to dump to channels. Writes to TrigCfg register once  //
// finished to clear capture_done bit in capture. Uses waddr and set_capture_done from      //
// capture as write address and TrigCfg output control.                                    //
////////////////////////////////////////////////////////////////////////////////////////////

module cmd_cfg(
   clk, rst_n, resp, send_resp, resp_sent, cmd, cmd_rdy, clr_cmd_rdy, 
   set_capture_done, raddr, rdataCH1, rdataCH2, rdataCH3, rdataCH4, 
   rdataCH5, waddr, trig_pos, decimator, maskL, maskH, matchL, matchH, 
   baud_cntL, baud_cntH, TrigCfg, CH1TrigCfg, CH2TrigCfg, CH3TrigCfg, 
   CH4TrigCfg, CH5TrigCfg, VIH, VIL
);

   // parameters		   
   parameter ENTRIES = 384;	               // defaults to 384 for simulation, use 12288 for DE-0
   parameter LOG2 = 9;		                  // Log base 2 of number of entries
       
   // input signals
   input logic clk, rst_n;                   // system clock and active low reset
   input logic [15:0] cmd;			            // 16-bit command from UART (host) to be executed
   input logic cmd_rdy;				            // indicates command is valid
   input logic resp_sent;			            // indicates transmission of resp[7:0] to host is complete
   input logic set_capture_done;			      // from the capture module (sets capture done bit in TrigCfg)
   input logic [LOG2-1:0] waddr;			      // on a dump raddr is initialized to waddr
   input logic [7:0] rdataCH1;			      // read data from RAMqueues
   input logic [7:0] rdataCH2, rdataCH3;
   input logic [7:0] rdataCH4, rdataCH5;

   // internal signals
   logic [7:0] prev_resp; 			            // save response sent when dumping
   logic write_en;       			            // enables FF to write data
   logic [7:0] trig_posH, trig_posL; 		   // lower and upper byte of trig_pos
   logic inc_raddr;                          // increment raddr until response sent
   logic load_raddr;                         // load at beginning of dump
   logic [LOG2-1:0] addr_cnt;                // address counter

   // output signals
   output logic [7:0] resp;			         // data to send to host as response (formed in SM)
   output logic send_resp;			            // used to initiate transmission to host (via UART)
   output logic clr_cmd_rdy;			         // when finished processing command use this to knock down cmd_rdy
   output logic [LOG2-1:0] raddr;		      // read address to RAMqueues (same address to all queues)
   output logic [LOG2-1:0] trig_pos;		   // how many sample after trigger to capture
   output reg [3:0] decimator;			      // goes to clk_rst_smpl block
   output reg [7:0] maskL, maskH;			   // to trigger logic for protocol triggering
   output reg [7:0] matchL, matchH;		      // to trigger logic for protocol triggering
   output reg [7:0] baud_cntL, baud_cntH;		// to trigger logic for UART triggering
   output reg [5:0] TrigCfg;			         // some bits to trigger logic, others to capture unit
   output reg [4:0] CH1TrigCfg, CH2TrigCfg;	// to channel trigger logic
   output reg [4:0] CH3TrigCfg, CH4TrigCfg;	// to channel trigger logic
   output reg [4:0] CH5TrigCfg;			      // to channel trigger logic
   output reg [7:0] VIH, VIL;			         // to dual_PWM to set thresholds

   // state definition
   typedef enum reg[2:0] {IDLE, DUMP, WRITE, READ, DUMP_RETRIEVE, DUMP_SEND} state_t;
   state_t state, nxt_state;

   // continous assignments
   assign trig_pos = {trig_posH, trig_posL}; // set trig_pos to its upper and lower bytes

   // state machine flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) state <= IDLE;
      else state <= nxt_state;
   end

   // state machine combinational logic
   always_comb begin

      // default outputs
      send_resp = 0;
      clr_cmd_rdy = 0;
      write_en = 0;
      nxt_state = state;
      load_raddr = 0;
      inc_raddr = 0;
      resp = '0;
      
      case (state)

         // IDLE state
         default : if (cmd_rdy) begin
            case (cmd[15:14])            		// get the DUMP channel and send the corresponding resp
               2'b00: nxt_state = READ;
               2'b01: nxt_state = WRITE;
               2'b10: begin 
                    load_raddr = 1; 
                    nxt_state = DUMP; 
                end
               default: begin
	               resp = 8'hEE;              // send negative response if cmd did not equal READ, WRITE, or DUMP
		            send_resp = 1;
	            end
            endcase
         end
         
         // READ data
         READ : begin                        	
               case (cmd[13:8])                 // set the resp based on the middle byte of cmd register signal
                  6'h00: resp = TrigCfg;
                  6'h01: resp = CH1TrigCfg;
                  6'h02: resp = CH2TrigCfg;
                  6'h03: resp = CH3TrigCfg;
                  6'h04: resp = CH4TrigCfg;
                  6'h05: resp = CH5TrigCfg;
                  6'h06: resp = decimator;
                  6'h07: resp = VIH;
                  6'h08: resp = VIL;
                  6'h09: resp = matchH;
                  6'h0A: resp = matchL;
                  6'h0B: resp = maskH;
                  6'h0C: resp = maskL;
                  6'h0D: resp = baud_cntH;
                  6'h0E: resp = baud_cntL;
                  6'h0F: resp = trig_posH;
                  6'h10: resp = trig_posL;
                  default: resp = 8'hEE;             // negative acknowledgement if no matches
               endcase
               send_resp = 1;
               clr_cmd_rdy = 1;
               nxt_state = IDLE;
         end

         // WRITE data
         WRITE : begin
              write_en = 1;
              resp = 8'hA5;               	// send positive acknowledgement and clear cmd_rdy
              send_resp = 1;
              clr_cmd_rdy = 1;            
              nxt_state = IDLE;
         end

         // start DUMP cycle. 1st state allows for raddr to be selected at correct time
         DUMP : begin
            nxt_state = DUMP_RETRIEVE;
         end

         // DUMP_RETRIEVE - read data from correct channel into dump
         DUMP_RETRIEVE: begin
            case (cmd[10:8])            		// get the DUMP channel and send the corresponding resp
               3'b001: resp = rdataCH1;
               3'b010: resp = rdataCH2;
               3'b011: resp = rdataCH3;
               3'b100: resp = rdataCH4;
               3'b101: resp = rdataCH5;
               default: resp = 8'hEE;        // negative acknowledgement if not found
            endcase
            send_resp = 1;
	         nxt_state = DUMP_SEND;
         end

	      // inner DUMP SM - loops through each addr of RAMqueue and sends resp
         DUMP_SEND : begin
	         if(resp_sent) begin
               inc_raddr = 1;
               if (addr_cnt == ENTRIES-1) begin       // done sending when addr_cnt = ENTRIES
                  clr_cmd_rdy = 1;        		      // after going through all samples RAMqueue, clear cmd_rdy
                  nxt_state = IDLE;
               end else
	            nxt_state = DUMP;	                     // allow send_resp to deassert before cycling to DUMP
            end
	      end
      endcase
   end

   ////////////// Flop Outputs ///////////////
   
   // address counter flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) addr_cnt <= '0;
      else if (inc_raddr) addr_cnt <= (addr_cnt + 1) % ENTRIES;  	// increment counter
   end

  // raddr flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) raddr <= '0;
      else if (load_raddr) raddr <= waddr % ENTRIES;
      else if (inc_raddr) raddr <= (raddr==ENTRIES-1) ? '0 : raddr + 1;  	// checks if writing is enabled and the cmd matches TrigCfg reg signal
   end

   // TrigCfg write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) TrigCfg <= 6'h03;
      else if (write_en && (cmd[13:8] == 6'h00)) TrigCfg <= cmd[5:0];  	// checks if writing is enabled and the cmd matches TrigCfg reg signal
      else if (set_capture_done) TrigCfg <= {2'b10, TrigCfg[3:0]}; // set capture bit (bit 5) and clear run bit (bit 4)
   end
      
   // CH1TrigCfg write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) CH1TrigCfg <= 5'h01;
      else if (write_en && (cmd[13:8] == 6'h01)) CH1TrigCfg <= cmd[4:0];
   end

   // CH2TrigCfg write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) CH2TrigCfg <= 5'h01;
      else if (write_en && (cmd[13:8] == 6'h02)) CH2TrigCfg <= cmd[4:0];
   end

   // CH3TrigCfg write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) CH3TrigCfg <= 5'h01;
      else if (write_en && (cmd[13:8] == 6'h03)) CH3TrigCfg <= cmd[4:0];
   end

   // CH4TrigCfg write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) CH4TrigCfg <= 5'h01;
      else if (write_en && (cmd[13:8] == 6'h04)) CH4TrigCfg <= cmd[4:0];
   end

   // CH5TrigCfg write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) CH5TrigCfg <= 5'h01;
      else if (write_en && (cmd[13:8] == 6'h05)) CH5TrigCfg <= cmd[4:0];
   end

   // Decimator write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) decimator <= 5'h00;
      else if (write_en && (cmd[13:8] == 6'h06)) decimator <= cmd[3:0];
   end

   // VIH write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) VIH <= 8'hAA;
      else if (write_en && (cmd[13:8] == 6'h07)) VIH <= cmd[7:0];
   end

   // VIL write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) VIL <= 8'h55;
      else if (write_en && (cmd[13:8] == 6'h08)) VIL <= cmd[7:0];
   end

   // matchH write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) matchH <= 8'h00;
      else if (write_en && (cmd[13:8] == 6'h09)) matchH <= cmd[7:0];
   end

   // matchL write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) matchL <= 8'h00;
      else if (write_en && (cmd[13:8] == 6'h0A)) matchL <= cmd[7:0];
   end

   // maskH write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) maskH <= 8'h00;
      else if (write_en && (cmd[13:8] == 6'h0B)) maskH <= cmd[7:0];
   end

   // maskL write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) maskL <= 8'h00;
      else if (write_en && (cmd[13:8] == 6'h0C)) maskL <= cmd[7:0];
   end

   // baud_cntH write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) baud_cntH <= 8'h06;
      else if (write_en && (cmd[13:8] == 6'h0D)) baud_cntH <= cmd[7:0];
   end

   // baud_cntL write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) baud_cntL <= 8'hC8;
      else if (write_en && (cmd[13:8] == 6'h0E)) baud_cntL <= cmd[7:0];
   end

   // trig_posH write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) trig_posH <= 8'h00;
      else if (write_en && (cmd[13:8] == 6'h0F)) trig_posH <= cmd[7:0];
   end

   // trig_posL write data flop
   always_ff @(posedge clk, negedge rst_n) begin
      if (!rst_n) trig_posL <= 8'h01;
      else if (write_en && (cmd[13:8] == 6'h10)) trig_posL <= cmd[7:0];
   end

endmodule
