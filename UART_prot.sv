///////////////////////////////////////////////////////////////////////////////////
// UART protocol triggering module takes in serial data from CH1L at baud rate. //
// Compares byte to match data while using masked bits as don't cares.         //
// UARTtrig asserted if there is a match.                                     //
///////////////////////////////////////////////////////////////////////////////

module UART_prot (
    clk, rst_n, RX, baud_cnt, match, mask, UARTtrig
);

    // input signals
    input clk, rst_n;               // system clock and active low reset
    input RX;                       // serial data in line. comes direct from VIL comparator of CH1
    input [7:0] match;              // specifies the data the UART_RX is looking to match
    input [7:0] mask;               // used to mask off bits of match to a don't care for comparison
    input [15:0] baud_cnt;          // specifies the baud rate of the UART in # of system clocks. From 2400 to 921600

    // internal signals
    logic shift, init, receiving, set_rdy, rdy, set_UART;       // state machine outputs
    logic RX_single_flopped, RX_double_flopped;                 // flop RX for meta stability purposes
    logic [15:0] baud_cnt_tracker;                              // shift when 0
    logic [3:0] shift_cnt;                                      // keep track of # of shifts 
    logic [8:0] rx_shift_reg;                                   // register for shifted data
    logic [7:0] masked_data, masked_match;                      // mask specified bits when comparing match data to RX

    // output signals
    output logic UARTtrig;          // Asserted for 1 clock cycle at end of a reception if data matches

    // state machine states, IDLE and RECV
    typedef enum reg {IDLE, RECV} state_t;
    state_t state, nxt_state;

    // continous assignments
    assign shift = (baud_cnt_tracker == 6'b000000);
    assign masked_data = rx_shift_reg[7:0] & ~mask;
    assign masked_match = match & ~mask;

    // state machine flops
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= nxt_state;
    end

    // state machine combinational logic
    always_comb begin

        /// default signals ///
        init = 1'b0;
        nxt_state = state;
        receiving = 1'b0;
        set_rdy = 0;
        set_UART = 0;

        case (state)

            // IDLE state - wait for RX to be low then initiate receiving
            IDLE : begin
                if (RX_double_flopped == 0) begin           // start when a new signal is in RX
                    init = 1'b1;
                    nxt_state = RECV;
                end
            end

            // RECV state - wait 10 shifts then stop receiving
            RECV : begin
                receiving = 1'b1;
                if (shift_cnt == 4'b1010) begin
                    if (masked_match == masked_data) set_UART = 1;      // data is equal to RX
                    receiving = 1'b0;
                    nxt_state = IDLE;
                    set_rdy = 1;                                        // done receiving
                end
            end
        endcase
    end

    // metastability flops
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            RX_single_flopped <= 1'b1;                                                  // reset to high
            RX_double_flopped <= 1'b1;                                                  // reset to high
        end
        else begin
            RX_single_flopped <= RX;                                                    // flop once
            RX_double_flopped <= RX_single_flopped;                                     // flop twice
        end
    end 

    // rx shifter
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) rx_shift_reg <= '1;
        else if (shift) rx_shift_reg <= {RX_double_flopped, rx_shift_reg[8:1]};         // perform a right shift and shift the bit in
    end

    // baud counter, counts down from 34 then asserts shift
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) baud_cnt_tracker <= baud_cnt / 2;                                   // reset to half the baud counter
        else if (init) baud_cnt_tracker <= baud_cnt / 2;                                // set to half the baud counter when first initialized
        else if (shift) baud_cnt_tracker <= baud_cnt;                                   // otherwise set to the full counter
        else if (receiving) baud_cnt_tracker <= baud_cnt_tracker - 1;                   // count down when receiving
    end

    // shift counter, does it 12 times: 2 for metastability, 1 for start bit, 8 for data, 1 for stop bit
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) shift_cnt <= 0; // reset to 0
        else if (set_rdy | init) shift_cnt <= 0;
        else if (shift) shift_cnt <= shift_cnt + 1;
    end

    // assert UARTtrig for one clock period when conditions match
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) UARTtrig <= 0;
        else if (set_UART) UARTtrig <= 1;
        else UARTtrig <= 0;
    end

    // rdy flop: assert when set_rdy is asserted
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) rdy <= 1'b0; // reset
        else if (init) rdy <= 1'b0;
        else if (set_rdy) rdy <= 1'b1;
    end

endmodule