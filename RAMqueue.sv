///////////////////////////////////////////////////////////////////
// RAMqueue module that stores data caputred from each channel. //
// 5 RAM blocks used per channel. Each RAM block stores data   //
// as 8-bit words with parametetizable depth. Contains read   //
// port and write port.                                      //
//////////////////////////////////////////////////////////////

module RAMqueue (
    clk, we, waddr, wdata, raddr, rdata
);

    // parameters
    parameter ENTRIES = 384;                    // depth of the RAM, default to 384
    parameter LOG2 = 9;                         // width of the address bus 

    // input signals
    input clk;                                  // system clock
    input we;                                   // active high write enable
    input [LOG2-1:0] waddr;                     // write address to select location to be written to
    input [7:0] wdata;                          // write data. drive with read data
    input [LOG2-1:0] raddr;                     // read address to select location to be read from.

    // output signals
    output reg [7:0] rdata;                     // read data. data available after next posedge of clk. read does not require enable

    // synopsys translate_off
    reg [7:0] mem[0:ENTRIES-1]; // 2048 entries of 8 bits

    // memory control flop
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;            // if write enabled, write the data input in to the address specified
        rdata <= mem[raddr];                    // always reading from memory
    end
    // synopsys translate_on

endmodule
