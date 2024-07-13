///////////////////////////////////////////////////////////////////////////////////////////////////
// Capture channel module captures data from the 5 channels and stores into circular RAMqueues. //
// Continue storing data until a configurable number of samples after trigger have occurred.   // 
// Must be armed and triggered to assert set_capture_done. set_capture_done deasserted once   //
// the command processing module has read the TrigCfg register.                              //
//////////////////////////////////////////////////////////////////////////////////////////////

module capture (clk, rst_n, wrt_smpl, run, capture_done, triggered, 
   trig_pos, we, waddr, set_capture_done, armed
);

  // parameters
  parameter ENTRIES = 384;                                          // defaults to 384 for simulation, use 12288 for DE-0
  parameter LOG2 = 9;                                               // Log base 2 of number of entries

  // input signals
  input clk;                                                        // system clock
  input rst_n;                                                      // active low asynch reset
  input wrt_smpl;                                                   // from clk_rst_smpl.  Lets us know valid sample ready
  input run;                                                        // signal from cmd_cfg that indicates we are in run mode
  input capture_done;                                               // signal from cmd_cfg register
  input triggered;                                                  // from trigger unit...we are triggered
  input [LOG2-1:0] trig_pos;                                        // How many samples after trigger do we capture

  // internal signals
  logic [LOG2-1:0] trig_cnt;  // number of samples captured
  logic run_rst;              // set waddr and trig_cnt to 0 when run starts
  logic inc_trig_cnt;         // tells flop to increment trig_cnt from SM logic
  logic inc_waddr;            // tells flop to increment waddr from SM logic
  logic set_armed;            // set if waddr + trig_pos == ENTRIES - 1 when not triggered
  logic clr_armed;            // clear after set_capture_done is asserted 

  // output signals
  output reg we;                // write enable to RAMs
  output reg [LOG2-1:0] waddr;  // write addr to RAMs
  output reg set_capture_done;  // asserted to set bit in cmd_cfg
  output reg armed;             // we have enough samples to accept a trigger

  /// declare state register as type enum, need default since 3 states ///
  typedef enum reg [1:0] {
    IDLE,
    WRITE,
    POST
  } state_t;
  state_t state, nxt_state;
  
  // state machine flop logic
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else state <= nxt_state;
  end

  // state machine combinational logic
  always_comb begin

    // default signals
    nxt_state = state;
    run_rst = 1'b0;
    inc_trig_cnt = 1'b0;
    inc_waddr = 1'b0;
    set_capture_done = 1'b0;
    set_armed = 1'b0;
    we = 1'b0;
    clr_armed = 0;
    
    case (state)

      // IDLE STATE - wait for run
      default: begin
        if (run) begin
          run_rst = 1'b1;
          nxt_state = WRITE;
        end
      end

      // WRITE STATE - wait for trigger count to match the desired number
      WRITE: begin

        if (wrt_smpl) begin
          if (triggered && trig_cnt == trig_pos) begin  // only set set_capture_done when triggered
            set_capture_done = 1'b1;
            clr_armed = 1;
            nxt_state = POST;
          end
          else begin                                              // continue writing to waddr if wrt_smpl is set
            we = 1'b1;
            inc_waddr = 1'b1;
            inc_trig_cnt = triggered;                             // start incrementing trig_cnt once triggered is set
            if ((waddr + trig_pos) == (ENTRIES - 1)) set_armed = 1'b1;    // set armed when waddr + trig_pos == ENTRIES - 1
          end
        end
      end

      // POST OPERATION STATE - wait for capture done to be cleared
      POST: if (~capture_done) nxt_state = IDLE;

    endcase

  end

  // armed flop: assert when the correct address has been found
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) armed <= 1'b0;
    else if (set_armed) armed <= 1'b1;                                            // correct address has been found
    else if (clr_armed) armed <= 1'b0;                                            // clear after set_capture_done
    
  end

  // waddr flop: increment the write address each write cycle
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) waddr <= 0;
    else if (run_rst) waddr <= '0;
    else if (inc_waddr) waddr <= (waddr == ENTRIES - 1) ? '0 : 
                                  waddr + 1;                                      // loop waddr to beginning if it exceeds ENTRIES - 1
  end

  // trig_cnt flop: number of cycles triggered has been asserted
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) trig_cnt <= '0;
    else if (run_rst) trig_cnt <= '0;
    else if (inc_trig_cnt) trig_cnt <= trig_cnt + 1;
  end

endmodule
