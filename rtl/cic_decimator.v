`timescale 1ns / 1ps
//
// Sinc^3 CIC (cascaded integrator-comb) decimator: turns the 1-bit PDM
// bitstream from the onboard microphone into signed OUT_WIDTH-bit PCM
// samples, decimating by RATIO. This is the standard structure PDM
// microphone datasheets and application notes recommend for PDM-to-PCM
// conversion -- three integrators running at the PDM bit rate, three
// combs running at the decimated sample rate -- and it needs no
// multiplier anywhere: every stage is an adder/subtractor, since the
// PDM input is already a 1-bit ("+-1") signal.
//
// Register growth: a CIC filter of order N and decimation RATIO needs
// ceil(N * log2(RATIO)) extra bits of headroom over the input width to
// represent its internal accumulators without losing information
// (Hogenauer, 1981). With N=3 and RATIO=64, log2(64)=6 exactly, so the
// growth is 3*6=18 bits; with a 1-bit (+-1) input that is ACC_WIDTH=19.
// None of the internal adders below saturate or clip -- they are left
// to wrap in 2's complement, which is exactly what makes CIC filters
// work: as long as every stage is at least ACC_WIDTH wide, the final
// comb output reconstructs the correct decimated value regardless of
// how many times an individual integrator itself has wrapped around.
// The last OUT_WIDTH bits of that ACC_WIDTH-wide result are the usable
// PCM sample; see scripts/cic_filter_calc.py for where ACC_WIDTH and the
// resulting frequency response come from.
//
module cic_decimator #(
    parameter RATIO      = 64,
    parameter ACC_WIDTH  = 19,
    parameter OUT_WIDTH  = 16
) (
    input  wire clk,
    input  wire rst,
    input  wire pdm_sample_en,              // one clk pulse per PDM bit period
    input  wire pdm_bit,                    // synchronized PDM data bit
    output reg  signed [OUT_WIDTH-1:0] pcm_out,
    output reg  pcm_valid                   // one clk pulse per decimated sample
);

    localparam DEC_CNT_W = $clog2(RATIO);

    // ---- integrator section, runs every PDM bit period ----
    reg signed [ACC_WIDTH-1:0] int1, int2, int3;
    wire signed [ACC_WIDTH-1:0] pdm_signed = pdm_bit ? {{(ACC_WIDTH-1){1'b0}}, 1'b1}
                                                      : {(ACC_WIDTH){1'b1}}; // -1

    always @(posedge clk) begin
        if (rst) begin
            int1 <= {ACC_WIDTH{1'b0}};
            int2 <= {ACC_WIDTH{1'b0}};
            int3 <= {ACC_WIDTH{1'b0}};
        end else if (pdm_sample_en) begin
            int1 <= int1 + pdm_signed;
            int2 <= int2 + int1;
            int3 <= int3 + int2;
        end
    end

    // ---- decimation: keep one integrator sample out of every RATIO ----
    reg [DEC_CNT_W-1:0] dec_cnt;
    wire dec_en = pdm_sample_en && (dec_cnt == RATIO - 1);

    always @(posedge clk) begin
        if (rst)
            dec_cnt <= {DEC_CNT_W{1'b0}};
        else if (pdm_sample_en)
            dec_cnt <= dec_en ? {DEC_CNT_W{1'b0}} : dec_cnt + 1'b1;
    end

    // ---- comb section, runs once per decimated sample ----
    reg signed [ACC_WIDTH-1:0] x0, x0_prev;
    reg signed [ACC_WIDTH-1:0] comb1, comb1_prev;
    reg signed [ACC_WIDTH-1:0] comb2, comb2_prev;
    reg signed [ACC_WIDTH-1:0] comb3;

    always @(posedge clk) begin
        if (rst) begin
            x0 <= 0; x0_prev <= 0;
            comb1 <= 0; comb1_prev <= 0;
            comb2 <= 0; comb2_prev <= 0;
            comb3 <= 0;
            pcm_valid <= 1'b0;
            pcm_out   <= {OUT_WIDTH{1'b0}};
        end else if (dec_en) begin
            x0         <= int3;
            x0_prev    <= x0;
            comb1      <= x0 - x0_prev;
            comb1_prev <= comb1;
            comb2      <= comb1 - comb1_prev;
            comb2_prev <= comb2;
            comb3      <= comb2 - comb2_prev;
            // comb3 here is last cycle's result (nonblocking read), i.e.
            // exactly the pcm_out this same always block registers below
            pcm_out    <= comb3 >>> (ACC_WIDTH - OUT_WIDTH);
            pcm_valid  <= 1'b1;
        end else begin
            pcm_valid <= 1'b0;
        end
    end

endmodule
