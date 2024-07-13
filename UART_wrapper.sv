///////////////////////////////////////////////////////
// UART Wrapper module that packages 2 byte command // 
// from host PC into a single command.             //
////////////////////////////////////////////////////

module UART_wrapper(
    clk, rst_n, RX, TX, cmd_rdy, clr_cmd_rdy, cmd, send_resp, resp, resp_sent
);

    // input signals
    input clk, rst_n;		// system clock and active low reset
	input RX;				// Serial line that commands are sent on
	input clr_cmd_rdy;		// External input to clear cmd_rdy (bookkeeping)
	input send_resp;		// Simply connects to trmt of UART_tx inside UART_wrapper
	input [7:0] resp;		// Response being sent by logic analyzer to software

    // internal signals
    logic capture_first_byte;   // SM output, assign high byte to rx_data when asserted
    logic clr_rx_rdy; 		    // SM output, clear rx_rdy
    logic set_cmd_rdy;          // SM output, assert cmd_rdy
    logic [7:0] highByte; 		// stored high byte
    logic [7:0] rx_data;        // from rx_data in UART

    // output signals
    output logic TX;			// Serial data output
	output logic cmd_rdy;		// Indicates full 16-bit command is ready
    output logic resp_sent;		// Simply connects to tx_done of UART_tx inside UART_wrapper
	output [15:0]cmd;		    // The 16-bit command received

    // state type declaration
    typedef enum reg {IDLE, STORE_LOW} state_t;
    state_t state, nxt_state;

    // continous assignments
    assign cmd = {highByte, rx_data};                       // cmd is set to high byte, low byte

    // instantiate UART
    UART iUART(
        .clk(clk), .rst_n(rst_n), .RX(RX), .TX(TX), .rx_rdy(rx_rdy), .clr_rx_rdy(clr_rx_rdy), 
        .rx_data(rx_data), .trmt(send_resp), .tx_data(resp), .tx_done(resp_sent)
    );

    // state machine flop
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= nxt_state;
    end

    // state machine combinational logic
    always_comb begin

        // default signals
        nxt_state = state;
        set_cmd_rdy = 1'b0;
        capture_first_byte = 1'b0;
        clr_rx_rdy = 1'b0;

        case (state)

            // IDLE state - receive high byte until receieve signal rx_rdy goes high
            IDLE : begin
                if (rx_rdy) begin
                    nxt_state = STORE_LOW;
                    capture_first_byte = 1'b1;                 // store rx_data as highByte
                    clr_rx_rdy = 1'b1;
                end
            end

            // STORE_LOW state - receive low byte
            STORE_LOW : begin
                if (rx_rdy) begin
                    nxt_state = IDLE;
                    set_cmd_rdy = 1'b1;
                    clr_rx_rdy = 1'b1;
                end
            end

        endcase
        
    end

    // set the upper byte
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) highByte <= '0;                             // fill highByte
        else if (capture_first_byte) highByte <= rx_data;
    end

    // flop cmd_rdy
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) cmd_rdy <= 1'b0;
        else if (clr_cmd_rdy | nxt_state == STORE_LOW) cmd_rdy <= 1'b0;      // reset any time a new bit is entered
        else if (set_cmd_rdy) cmd_rdy <= 1'b1;
    end

endmodule