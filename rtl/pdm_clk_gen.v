`timescale 1ns / 1ps
//
// Divides the 100 MHz board clock down to the bit clock the PDM
// microphone samples on. SPK0833LM4H (the mic populated on this board,
// per Real Digital's Blackboard user manual) accepts a clock between
// 1.0 MHz and 3.25 MHz; dividing by 32 gives 100,000,000 / 32 =
// 3,125,000 Hz, comfortably inside that range with a clean integer
// divide and a free-running 50% duty cycle.
//
// DIV_W is the counter width; the generated clock period is 2^DIV_W
// system clock cycles, so DIV_W = 5 gives the divide-by-32 above.
//
module pdm_clk_gen #(
    parameter DIV_W = 5
) (
    input  wire clk,
    input  wire rst,
    output wire pdm_clk,     // 50% duty, toggles on the counter's MSB
    output wire pdm_tick     // one clk-cycle pulse on pdm_clk's rising edge
);

    reg [DIV_W-1:0] div_cnt;

    always @(posedge clk) begin
        if (rst)
            div_cnt <= {DIV_W{1'b0}};
        else
            div_cnt <= div_cnt + 1'b1;
    end

    assign pdm_clk  = div_cnt[DIV_W-1];
    // div_cnt[DIV_W-1] just became 1 the cycle div_cnt rolled from
    // 0111..1 to 1000..0, i.e. div_cnt now equals 2^(DIV_W-1) exactly.
    assign pdm_tick = (div_cnt == {1'b1, {(DIV_W-1){1'b0}}});

endmodule
