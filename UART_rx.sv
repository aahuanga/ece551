//////////////////////////////////////////////////////
// UART Receiver module that receives serial data  //
// at baud rate and outputs a byte.               //
///////////////////////////////////////////////////

module UART_rx(
    clk, rst_n, RX, clr_rdy, rx_data, rdy
);

    // input signals
    input clk, rst_n;				// 100MHz clk & active low reset
	input RX;						// Serial data input
    input clr_rdy;					// Knocks down rdy when asserted

    // internal signals
    logic shift, init, receiving, set_rdy;              // state machine signals
    logic RX_single_flopped, RX_double_flopped;         // double flop RX for metastability purposes
    logic [3:0] shift_cnt;                              // keep track of # of times shifted
    logic [5:0] baud_cnt;                               // start sampling in middle of cycle (baud / 2), continue counting down from baud. Baud = 32.
    logic [8:0] rx_shift_reg;                           // store shifted RX

    // output signals
    output [7:0] rx_data;			    // Byte received
	output logic rdy;					// Asserted when byte received, stays high till next start bit or clr_rdy asserted

    // state machine states, IDLE and RECV
    typedef enum reg {IDLE, RECV} state_t;
    state_t state, nxt_state;
    
    // continous assignments
    assign rx_data = rx_shift_reg[7:0]; // last bits of the data going into the shift register
    assign shift = (baud_cnt == 6'b000000); // assert shift when count is 0

    // state machine flop
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) state <= IDLE; 
        else state <= nxt_state;
    end

    // state machine combinational logic
    always_comb begin

        // default outputs
        init = 1'b0;
        nxt_state = state;
        receiving = 1'b0;
        set_rdy = 1'b0;

        case (state)

            // IDLE state - wait for RX to be low then initiate receiving
            IDLE : begin
                if ((RX_double_flopped == 0)) begin
                    init = 1'b1;
                    nxt_state = RECV;
                end
            end

            // RECV state - wait 10 shifts then stop receiving
            RECV : begin
                receiving = 1'b1;
                if (shift_cnt == 4'b1010) begin
                    receiving = 1'b0;
                    set_rdy = 1'b1;
                    nxt_state = IDLE;
                end
            end
            
        endcase
    end

    // rx flop for metastability
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            RX_single_flopped <= 1'b1;                                                      // reset to high
            RX_double_flopped <= 1'b1;                                                      // reset to high
        end
        else begin
            RX_single_flopped <= RX;                                                        // flop once
            RX_double_flopped <= RX_single_flopped;                                         // flop twice
        end
    end 

    // rx shifter
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) rx_shift_reg <= '1;
        else if (shift) rx_shift_reg <= {RX_double_flopped, rx_shift_reg[8:1]};             // perform a right shift and shift the bit in
    end

    // baud counter, counts down from 32 then asserts shift
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) baud_cnt <= 6'b010000;                                                  // reset to 16
        else if (init) baud_cnt <= 6'b010000;                                               // set to 16 when first initialized
        else if (shift) baud_cnt <= 6'b100000;                                              // otherwise set to 32
        else if (receiving) baud_cnt <= baud_cnt - 1;                                       // count down when receiving
    end

    // shift counter, does it 12 times: 2 for metastability, 1 for start bit, 8 for data, 1 for stop bit
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) shift_cnt <= '0;                                                          // reset to 0
        else if (set_rdy | init) shift_cnt <= '0;
        else if (shift) shift_cnt <= shift_cnt + 1;
    end

    // rdy flop, assert when set_rdy is asserted
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) rdy <= 1'b0;                                                            // asynchronous reset
        else if (init | clr_rdy) rdy <= 1'b0;
        else if (set_rdy) rdy <= 1'b1;
    end

endmodule