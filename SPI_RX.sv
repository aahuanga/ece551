//////////////////////////////////////////////////////////////////////////////////////////////
// SPI monarch module that receives MOSI on edg input specfified edge of SCLK. After MOSI  //
// is shifted into the receive register, the data is compared to match[15:0]. Bits where  //
// mask is high are treated as don't cares. len8 can be used to only compare against     //
// the lower 8 bits of the receieved data.                                              //
/////////////////////////////////////////////////////////////////////////////////////////

// ** NOTE: SPI LEN 8 NEG does not work **

module SPI_RX(
  clk, rst_n, SS_n, MOSI, SCLK, edg, len8, mask, match, SPItrig
);

  // input signals
  input clk;		                        // system clock
  input rst_n;		                      // reset
  input SS_n;		                        // SPI protocol signals
  input MOSI;
  input SCLK;		
  input edg;		                        // when high the receive shift register should shift on SCLK rise
  input len8;		                        // when high we are doing an 8-bit comparison to match[7:0]
  input [15:0] mask;	                  // used to mask off bits of match to a don?t care for comparison
  input [15:0] match;               	  // data unit is looking to match for a trigger

  // internal signals
  logic SCLK_int;		                    // intermediate SCLK signal
  logic SCLK_meta_free;		              // double-flopped SCLK signal, free of metastability
  logic SCLK_edge;		                  // additional flop of SCLK used for edge detection
  logic shift;			                    // control input for shift register
  logic done;			                      // indicates our SPI transaction is complete
  logic SCLK_rise;		                  // indicates a rising edge of SCLK
  logic SCLK_fall;		                  // indicates a falling edge of SCLK
  logic [15:0] shift_reg;	              // holds MOSI line
  logic SS_int;			                    // intermediate SS_n signal
  logic SS_meta_free;		                // double-flopped SS_n signal, free of metastability
  logic [15:0] match_masked;	          // masked match signal
  logic [15:0] shift_reg_masked;        // masked shift_reg signal
  logic MOSI_int;		                    // intermediate MOSI signal
  logic MOSI_meta_free;		              // double-flopped MOSI signal, free of metastability
  logic MOSI_edge;		                  // additional flop of MOSI used for edge detection

  // output signal
  output SPItrig;	                      // asserted for 1 clock cycle at end of areception if received data matches match[7:0]

  // state declaration
  typedef enum reg {IDLE, RX} state_t;
  state_t state, nxt_state;

  // continous assignments
  // determine if rising or falling edge
  assign SCLK_rise = (!SCLK_meta_free && SCLK_edge)? 1'b1 : 1'b0;	                        // rise if low to high
  assign SCLK_fall = (SCLK_meta_free && !SCLK_edge)? 1'b1 : 1'b0;	                        // fall if high to low
  // match logic
  assign match_masked = match & ~mask;
  assign shift_reg_masked = shift_reg & ~mask;
  assign SPItrig = (!rst_n) ? 1'b0 : 
                  (len8) ? ((match_masked[7:0] == shift_reg_masked[7:0]) && done) :      // if len8
                  ((match_masked == shift_reg_masked) && done);                          // compare both bytes

  // state machine flop
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else state <= nxt_state;
  end

  // state machine combinational logic
  always_comb begin
    
    ///// default outputs /////
    shift = 1'b0;
    done = 1'b0;
    nxt_state = state;

    case (state)
      // IDLE - wait for flopped SS_n to go low before receiving
      IDLE : if (!SS_meta_free)
        nxt_state = RX;	

      // RX - receive data
      RX : begin
        if (SS_meta_free) begin                                        // SPI transaction is complete
          done = 1'b1;                                                 // set for 1 cycle
          nxt_state = IDLE;
        end

        else if((!edg && SCLK_fall) || (edg && SCLK_rise))	           // set shift on appropriate SCLK edge
          shift = 1'b1;
      end
    endcase
  end

  // intermediate flop for SCLK, SS_n, MOSI
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
      SCLK_int <= 1'b1;
      SS_int <= 1'b1;
      MOSI_int <= 1'b0;
    end else begin
      SCLK_int <= SCLK;
      SS_int <= SS_n;
      MOSI_int <= MOSI;
    end
  end

  // double flop for SCLK, SS_N, MOSI
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
      SCLK_meta_free <= 1'b1;
      SS_meta_free <= 1'b1;
      MOSI_meta_free <= 1'b0;
    end else begin
      SCLK_meta_free <= SCLK_int;
      SS_meta_free <= SS_int;
      MOSI_meta_free <= MOSI_int;
    end
  end

  // edge detection register for SCLK, MOSI
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
      SCLK_edge <= 1'b1;
      MOSI_edge <= 1'b0;
    end else begin
      SCLK_edge <= SCLK_meta_free;
      MOSI_edge <= MOSI_meta_free;
    end
  end

  // shift register
  always_ff @(posedge clk, negedge rst_n) begin	
    if (!rst_n) shift_reg <= '0;
    else if (shift) shift_reg <= {shift_reg[14:0], MOSI_edge};
  end

endmodule
