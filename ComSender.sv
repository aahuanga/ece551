//////////////////////////////////////////////////////////
// Comsender module takes a 16-bit command and sends   //
// it as 2 bytes with the high byte being sent first. //
///////////////////////////////////////////////////////

module ComSender(
  clk, rst_n, cmd, send_cmd, resp, resp_rdy, RX, TX, clr_resp_rdy, cmd_sent
);

  // input signals
  input clk;		                                    // system clock
  input rst_n;		                                  // active low reset
  input [15:0] cmd;	                                // command to be sent
  input send_cmd;	                                  // indicates to send a command
  input clr_resp_rdy;                               // external reset resp_rdy
  input RX;		                                      // serial data input

  // internal signals
  logic trmt;		                                    // asserted for 1 clock to initiate transmission
  logic [7:0] tx_data;	                            // byte to transmit
  logic tx_done;	                                  // asserted when byte is done transmitting. stays high till next byte transmitted.
  logic sel;		                                    // SM output that selects which byte of cmd to send
  logic set_cmd_snt;	                              // asserts the cmd_sent signal when asserted
  logic [7:0] low_byte;                           	// lower byte of cmd

  // output signals
  output TX;		                                    // serial data output
  output reg cmd_sent;	                            // indicates that a command was sent
  output [7:0] resp;	                              // response being sent to logic analyzer by software
  output resp_rdy;	                                // indicates that a response is ready

  // state definition
  typedef enum reg [1:0] {IDLE, SEND_HIGH, SEND_LOW} state_t;
  state_t state, nxt_state;

  // continous assignments
  assign tx_data = (sel) ? cmd[15:8] :              // choose which byte to transfer based on sel
                  low_byte;

  // instantiate UART
  UART iUART(
    .clk(clk), .rst_n(rst_n), .RX(RX), .trmt(trmt), .clr_rx_rdy(resp_rdy),
    .tx_data(tx_data), .TX(TX), .rx_rdy(resp_rdy), .tx_done(tx_done), .rx_data(resp)
  );

  // state machine flop
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else state <= nxt_state;
  end

  // state machine combinational logic
  always_comb begin

    // default outputs
    sel = 1'b1;                                 // transmit high byte first
    trmt = 1'b0;
    set_cmd_snt = 1'b0;
    nxt_state = state;

    case (state)

      ///// default case = IDLE /////
      default : if (send_cmd) begin             // start transmitting high byte when send_cmd is asserted
        trmt = 1'b1;
        nxt_state = SEND_HIGH;
      end

      SEND_HIGH : if (tx_done) begin	          // wait until high byte finishes transmitting
        sel = 1'b0;                             // send low byte
        trmt = 1'b1;	                          // begin transmission of low byte
        nxt_state = SEND_LOW;
      end

      SEND_LOW : begin
          sel = 1'b0;
          if (tx_done) begin	                  // wait until low byte finishes transmitting
            set_cmd_snt = 1'b1;	                // cmd_snt set when entire command is ready
            nxt_state = IDLE;
          end
      end

    endcase

  end

  // register to store lower cmd byte
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) low_byte <= '0;
    else if (send_cmd) low_byte <= cmd[7:0];	  // store lower cmd byte
  end

  // cmd_sent register
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) cmd_sent <= 1'b0;
    else if (send_cmd) cmd_sent <= 1'b0;
    else if (set_cmd_snt) cmd_sent <= 1'b1;
  end

endmodule
