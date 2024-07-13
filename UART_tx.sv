//////////////////////////////////////////////////////
// UART Transmitter module that transmits bytes as //
// serial data at baud rate.                      //
///////////////////////////////////////////////////

module UART_tx(
    clk, rst_n, TX, trmt, tx_data, tx_done
);

    // input signals
    input clk, rst_n;				// 100MHz system clock % active low reset
	input trmt;						// Asserted for 1 clock to initiate transmisssion
    input [7:0]tx_data;				// Byte to transmit
    
    // internal signals
    logic shift, init, transmitting, set_done;      // state machine outputs
    logic [3:0] bit_cnt;                            // keep track of # of shifts
    logic [5:0] baud_cnt;                           // count cycle length then assert shift. cycle len = 32
    logic [8:0] tx_shift_reg;                       // store shifted TX

    // output signals
    output TX;						// Serial data output
	output reg tx_done;				// Asserted when byte is done transmitting, stays high till next byte

    // state machine states, IDLE and TRMT
    typedef enum reg {IDLE, TRMT} state_t;
    state_t state, nxt_state;

    // continous assignments
    assign TX = tx_shift_reg[0];                                            // last bit of the shift register
    assign shift = (baud_cnt == 6'b100000) ? 1'b1 : 1'b0;                   // assert shift when count is 32

    // state machine flops
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= nxt_state;
    end

    // state machine combinational logic
    always_comb begin

        // default outputs
        nxt_state = state;
        init = 1'b0;
        transmitting = 1'b0;
        set_done = 1'b0;

        case (state)

            // IDLE state - wait for transmit signal then instantiate transmission
            default : begin
                if (trmt) begin
                    init = 1'b1;
                    nxt_state = TRMT;
                end
            end

            // TRMT state - wait for 10 shifts to be asserted then stop transmission
            TRMT : begin
                transmitting = 1'b1;
                if (bit_cnt == 4'b1010) begin
                    set_done = 1'b1;
                    nxt_state = IDLE;
                end
            end

        endcase
        
    end

    // tx shifter
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) tx_shift_reg <= '1;
        else if (init) tx_shift_reg <= {tx_data, 1'b0};
        else if (shift) tx_shift_reg <= {1'b1, tx_shift_reg[8:1]};
    end

    // baud counter, counts to 34 then asserts shift
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) baud_cnt <= '0; // reset to 0
        else if (init | shift) baud_cnt <= '0;
        else if (transmitting) baud_cnt <= baud_cnt + 1;
    end

    // shift counter, does it 10 times
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) bit_cnt <= '0; // reset to 0
        else if (set_done | init) bit_cnt <= '0;
        else if (shift) bit_cnt <= bit_cnt + 1;
    end

    // flop final signal
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) tx_done <= 1'b0; // reset
        else if (init) tx_done <= 1'b0;
        else if (set_done) tx_done <= 1'b1;
    end

endmodule