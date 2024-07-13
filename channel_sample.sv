////////////////////////////////////////////////////////////////////////////////////////
// Channel sample module. Digital core stores each sample to the channel's RAM bank. //
// Each sample is comprised of different flopped versions of channel inputs from    //
// VIL and VIH comparators. Produces inputs for chnnl_trig module.                 //
////////////////////////////////////////////////////////////////////////////////////

module channel_sample(
    smpl_clk, clk, CH_H, CH_L, CH_Hff5, CH_Lff5, smpl
);

// input signals
input smpl_clk;                      // This is the decimated clock from clk_rst_smpl. Samples are captured on the negative edge of this clock
input clk; 						     // 100MHz system clock. This is used to flop the 8-bit accumulation of 4 2-bit samples.
input CH_H, CH_L; 				     // These are the unsynchronized channel samples from the comparators comparing against VIH, VIL

// internal signals
logic CH_Hff1, CH_Hff2, CH_Hff3, CH_Hff4;   // intermediate CH_H signals
logic CH_Lff1, CH_Lff2, CH_Lff3, CH_Lff4;   // intermediate CH_L signals

// output signals
output logic CH_Hff5, CH_Lff5; 		    // These are the 5th flopped versions of the channels. They go on to the trigger logic
output logic [7:0]smpl; 			// This is the 8-bit sample that will get written to the RAMqueue that channel. It is a collection of 4 2-bit samples);


// flop CH_H and CH_L 5 times each
always_ff @(negedge smpl_clk) begin

    // update each CH_H flop
    CH_Hff1 <= CH_H;
    CH_Hff2 <= CH_Hff1;
    CH_Hff3 <= CH_Hff2;
    CH_Hff4 <= CH_Hff3;
    CH_Hff5 <= CH_Hff4;

    // update each CH_L flop
    CH_Lff1 <= CH_L;
    CH_Lff2 <= CH_Lff1;
    CH_Lff3 <= CH_Lff2;
    CH_Lff4 <= CH_Lff3;
    CH_Lff5 <= CH_Lff4;
    
end

// flop 8-bit accumulation of 4 2-bit samples
always_ff @(posedge clk) begin
    smpl <= {CH_Hff2, CH_Lff2, CH_Hff3, CH_Lff3, CH_Hff4, CH_Lff4, CH_Hff5, CH_Lff5};
end

endmodule