//////////////////////////////////////////////////////////////////////////////////////
// Dual Pulse Width Modulation module. High threshold sets duty rate to VIH level. //
// Low sets duty to VIL level. Channels are compared to both signals and are      //
// considered high if both are high or low if both are low. Otherwise, the       //
// channel is considered mid rail.                                              //
/////////////////////////////////////////////////////////////////////////////////

module dual_PWM(
  clk, rst_n, VIL, VIH, VIL_PWM, VIH_PWM  
);

// input signals
input clk, rst_n;
input [7:0] VIL, VIH;

// output signals
output logic VIL_PWM, VIH_PWM;

// structural instantiation
pwm8 lowThreshold(
  .clk(clk), .rst_n(rst_n), .duty(VIL), .PWM_sig(VIL_PWM)
);
pwm8 highThreshold(
  .clk(clk), .rst_n(rst_n), .duty(VIH), .PWM_sig(VIH_PWM)
);

endmodule