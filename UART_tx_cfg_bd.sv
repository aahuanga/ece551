///////////////////////////////////////////////////////////////
// UART transmitter with configurable baud rate. Transmits  //
// bytes as serial data and asserts tx_done when complete. //
// TX used as an input to UART_prot.                      //
///////////////////////////////////////////////////////////

module UART_tx_cfg_bd (
    clk, rst_n, TX, trmt, tx_data, tx_done, baud
);

    // input signals
    input clk, rst_n, trmt;
    input [7:0] tx_data;
    input [15:0] baud;

    // internal signals
    logic shift, init, transmitting, set_done;
    logic [15:0] baud_cnt_tracker;
    logic [3:0] shift_cnt;
    logic [8:0] tx_shift_reg;

    // output signals
    output logic TX, tx_done;

    // state machine states, IDLE and TRMT
    typedef enum reg {IDLE, TRMT} state_t;
    state_t state, nxt_state;

    // continous assignments
    assign TX = tx_shift_reg[0];                                // last bit of the shift register
    assign shift = (baud_cnt_tracker == 0);                     // assert shift when count is 0

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

            // in IDLE state, wait for transmit signal then instantiate transmission
            default : begin
                if (trmt) begin
                    init = 1'b1;
                    nxt_state = TRMT;
                end
            end

            // in TRMT state, wait for 10 shifts to be asserted then stop transmission
            TRMT : begin
                transmitting = 1'b1;
                if (shift_cnt == 4'b1010) begin
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
        if (!rst_n) baud_cnt_tracker <= baud;
        else if (init | shift) baud_cnt_tracker <= baud;
        else if (transmitting) baud_cnt_tracker <= baud_cnt_tracker - 1;
    end

    // shift counter, does it 10 times
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) shift_cnt <= 4'b0000; // reset to 0
        else if (init) shift_cnt <= 4'b0000;
        else if (shift) shift_cnt <= shift_cnt + 1;
    end

    // flop final signal
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) tx_done <= 1'b0; // reset
        if (init) tx_done <= 1'b0;
        else if (set_done) tx_done <= 1'b1;
    end

endmodule