`timescale 1ns / 1ps
//
// First-order, error-feedback delta-sigma DAC: turns a signed IN_WIDTH
// PCM sample into a single output bit, toggled every system clock cycle,
// whose running average tracks the PCM value. The speaker pin on this
// board ("audio", per Real Digital's master XDC) is documented as
// accepting either PWM or PDM drive, so this 1-bit, heavily oversampled
// stream is a valid drive for it directly, with no external DAC needed.
//
// Classic error-feedback structure: integrate (input - last quantizer
// error), quantize the running sum to +-FULL_SCALE, and keep whatever
// the quantizer got wrong as next cycle's error. Run at the full 100 MHz
// system clock against a PCM input that only changes once every CIC
// decimated sample period, the oversampling ratio (OSR) is
// 100,000,000 / 48,828.125 = 2048, which is what pushes quantization
// noise up out of the audio band; see scripts/delta_sigma_calc.py for
// the resulting in-band SNR.
//
module delta_sigma_dac #(
    parameter IN_WIDTH  = 16,
    parameter ACC_WIDTH = 18
) (
    input  wire clk,
    input  wire rst,
    input  wire signed [IN_WIDTH-1:0]  pcm_in,
    output reg                          dac_out   // drives the speaker pin
);

    // symmetric +-full scale reference; the 1 LSB asymmetry of two's
    // complement (-32768 has no positive match) is not worth the extra
    // logic to special-case for an audio signal
    localparam signed [ACC_WIDTH-1:0] FULL_SCALE = (1 <<< (IN_WIDTH - 1)) - 1;

    wire signed [ACC_WIDTH-1:0] in_ext =
        {{(ACC_WIDTH - IN_WIDTH){pcm_in[IN_WIDTH-1]}}, pcm_in};

    reg  signed [ACC_WIDTH-1:0] err_acc;
    wire signed [ACC_WIDTH-1:0] sum = err_acc + in_ext;

    always @(posedge clk) begin
        if (rst) begin
            err_acc <= {ACC_WIDTH{1'b0}};
            dac_out <= 1'b0;
        end else if (sum >= 0) begin
            dac_out <= 1'b1;
            err_acc <= sum - FULL_SCALE;
        end else begin
            dac_out <= 1'b0;
            err_acc <= sum + FULL_SCALE;
        end
    end

endmodule
