//////////////////////////////////////////////////////
// Pulse Width Modulation module. PWM-sig high for //
// [duty]% of clk period.                         //
///////////////////////////////////////////////////

module pwm8(
    clk, rst_n, duty, PWM_sig
);

    input clk, rst_n;               // system clock and active low reset
    logic [7:0] cnt;                // current number of cycles
    logic cnt_less_than_duty;       // assert when count is less than duty
    input [7:0] duty;               // specified number of cycles to wait for, used as percent of cycle length
    output logic PWM_sig;           // assert while cnt is less than duty

    // assert 1 when the count is less than the specified duty cycle
    assign cnt_less_than_duty = (cnt <= duty) & (cnt != 8'b11111111);

    // pwm signal logic
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) PWM_sig <= 1'b1;
        else PWM_sig <= cnt_less_than_duty;
    end

    // counter logic
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) cnt <= '0;
        else cnt <= cnt + 1;
    end

endmodule