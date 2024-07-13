////////////////////////////////////////////////////////////////////////////////////////
// Channel trig module. Digital core stores each sample to the channel's RAM bank.   //
// Each sample is comprised of different flopped versions of channel inputs from    //
// VIL and VIH comparators. Produces inputs for chnnl_trig module.                 //
////////////////////////////////////////////////////////////////////////////////////

module chnnl_trig(
  clk, rst_n, CH_TrigCfg, armed, CH_Lff5, CH_Hff5, CH_Trig
);

  // input signals
  input clk;			                // system clock
  input rst_n;			              // active-low asynch reset
  input [4:0] CH_TrigCfg;	        // x is between 1-5 for each channel. Inputs come from register in cmd_cfg
  input armed;			              // can't allow the edge trigger until after armed is asserted
  input CH_Lff5;		              // channel data for low or falling edge triggers
  input CH_Hff5;		              // channel data for high or falling edge triggers

  // internal signals
  logic rise_edg;		              // positive edge. If set a positive edge on channel is required for trigger
  logic rise_edg_meta_free;	      // double-flopped rise_edg signal free of metastability
  logic fall_edg;		              // negative edge. If set a negative edge on channel is required for trigger
  logic fall_edg_meta_free;	      // double-flopped fall_edg signal free of metastability
  logic high_lvl;		              // high level. If set this channel must be high for trigger to occur
  logic low_lvl;		              // low level. If set this channel must be low for trigger to occur

  // output signals
  output CH_Trig;		              // channel trigger output

  // continous assignments
  // CH_Trig logic. At least 1 high level is high or low level is low to set.
  assign CH_Trig = (
    (rise_edg_meta_free && CH_TrigCfg[4]) || 
    (fall_edg_meta_free && CH_TrigCfg[3]) || 
    (high_lvl && CH_TrigCfg[2]) || 
    (low_lvl && CH_TrigCfg[1]) || 
    CH_TrigCfg[0]
  );

  // rising edge register
  always_ff @(posedge CH_Hff5, negedge armed) begin
    if (!armed) rise_edg <= 1'b0;
    else rise_edg <= 1'b1;
  end

  // double flop rise_edg
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) rise_edg_meta_free <= 1'b0;
    else rise_edg_meta_free <= rise_edg;
  end

  // falling edge register
  always_ff @(negedge CH_Lff5, negedge armed) begin
    if (!armed) fall_edg <= 1'b0;
    else fall_edg <= 1'b1;
  end

  // double flop fall_edg
  always_ff @(posedge clk, negedge rst_n) begin	
    if (!rst_n) fall_edg_meta_free <= 1'b0;
    else fall_edg_meta_free <= fall_edg;
  end

  // high level register
  always_ff @(posedge clk, negedge rst_n) begin	
    if (!rst_n) high_lvl <= 1'b0;
    else high_lvl <= CH_Hff5;
  end

  // low level register
  always_ff @(posedge clk, negedge rst_n) begin	
    if (!rst_n) low_lvl <= 1'b0;
    else low_lvl <= ~CH_Lff5;
  end

endmodule