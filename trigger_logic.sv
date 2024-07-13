//////////////////////////////////////////////////////////////
// Protocol Trigger Logic module. Triggered if all trigger //
// sources are high & armed & logic has captured channels //
// into RAMqueue.                                        //
//////////////////////////////////////////////////////////

module trigger_logic(
    clk, rst_n, armed, set_capture_done, triggered,
    CH1Trig, CH2Trig, CH3Trig, CH4Trig, CH5Trig, protTrig
);

    // input signals
    input clk, rst_n;               // System clock and active low reset
    input armed;                    // Indicates enough samples have been acquired so triggered can be accepted
    input set_capture_done;         // Asserted once logic analyzer has finished capturing channels into RAMqueue
    input CH1Trig, CH2Trig, CH3Trig, CH4Trig, CH5Trig, protTrig;    // trigger sources

    // output signal
    output logic triggered;         // set when all trigger sources are high

    // trigger logic flop
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) triggered <= 1'b0;
        else if (set_capture_done) triggered <= 1'b0;
        else if (armed & CH1Trig & CH2Trig & CH3Trig & CH4Trig & CH5Trig & protTrig) triggered <= 1'b1;
    end

endmodule