`timescale 1ns / 1ps
//
// Peak-with-decay envelope follower driving an 8-level LED bar graph,
// plus a separate clip indicator. Updates once per decimated PCM sample
// (pcm_valid, at the CIC's ~48.8 kHz output rate): on a new sample, the
// envelope jumps up to the sample's magnitude immediately if it is
// louder, otherwise it leaks down by 1/2^DECAY_SHIFT of itself every
// sample, giving a decay time constant of roughly 2^DECAY_SHIFT sample
// periods (see scripts/cic_filter_calc.py for the exact number at the
// chosen DECAY_SHIFT).
//
module vu_meter #(
    parameter IN_WIDTH    = 16,
    parameter DECAY_SHIFT = 6
) (
    input  wire clk,
    input  wire rst,
    input  wire signed [IN_WIDTH-1:0] pcm_in,
    input  wire                        pcm_valid,
    output reg  [7:0]                  bar,     // thermometer-coded, 8 levels
    output reg                         clip      // set when the envelope hits >=~98% full scale
);

    localparam [IN_WIDTH-2:0] FULL_SCALE = (1 <<< (IN_WIDTH - 1)) - 1;

    // 8 evenly spaced linear thresholds up to full scale
    localparam [IN_WIDTH-2:0] TH1 = FULL_SCALE * 1 / 8;
    localparam [IN_WIDTH-2:0] TH2 = FULL_SCALE * 2 / 8;
    localparam [IN_WIDTH-2:0] TH3 = FULL_SCALE * 3 / 8;
    localparam [IN_WIDTH-2:0] TH4 = FULL_SCALE * 4 / 8;
    localparam [IN_WIDTH-2:0] TH5 = FULL_SCALE * 5 / 8;
    localparam [IN_WIDTH-2:0] TH6 = FULL_SCALE * 6 / 8;
    localparam [IN_WIDTH-2:0] TH7 = FULL_SCALE * 7 / 8;
    localparam [IN_WIDTH-2:0] TH8 = FULL_SCALE * 98 / 100;  // clip threshold

    reg [IN_WIDTH-2:0] envelope;  // unsigned magnitude, one sign bit narrower
    wire [IN_WIDTH-2:0] abs_pcm = pcm_in[IN_WIDTH-1] ? (~pcm_in[IN_WIDTH-2:0] + 1'b1)
                                                      : pcm_in[IN_WIDTH-2:0];
    wire [IN_WIDTH-2:0] decayed = envelope - (envelope >> DECAY_SHIFT);

    always @(posedge clk) begin
        if (rst) begin
            envelope <= {(IN_WIDTH-1){1'b0}};
            bar      <= 8'b0;
            clip     <= 1'b0;
        end else if (pcm_valid) begin
            envelope <= (abs_pcm > decayed) ? abs_pcm : decayed;

            bar[0] <= (envelope >= TH1);
            bar[1] <= (envelope >= TH2);
            bar[2] <= (envelope >= TH3);
            bar[3] <= (envelope >= TH4);
            bar[4] <= (envelope >= TH5);
            bar[5] <= (envelope >= TH6);
            bar[6] <= (envelope >= TH7);
            bar[7] <= (envelope >= TH8);
            clip   <= (envelope >= TH8);
        end
    end

endmodule
