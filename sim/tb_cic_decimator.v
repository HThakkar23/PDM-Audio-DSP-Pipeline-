`timescale 1ns / 1ps
//
// Self-checking testbench for cic_decimator.v. Written and checked by
// hand against the RTL above; no simulator is installed on this
// machine (same limitation as the other two Blackboard projects), so
// this has never actually been run. It drives pdm_sample_en/pdm_bit
// directly rather than going through pdm_clk_gen, since the decimator
// itself does not care how its enable pulse is generated.
//
// Steady-state DC gain of a 3rd order, 64:1 CIC is R^N = 64^3 = 262,144
// at the comb output, before the >>> (ACC_WIDTH-OUT_WIDTH) = >>>3 scale
// down to pcm_out; a constant bipolar (+-1) input x therefore settles,
// after enough decimated samples for the pipeline to fill, toward
// pcm_out ~= x * 262,144 / 8 = x * 32,768. A duty-cycle-d bitstream
// (d fraction of 1s, (1-d) fraction of 0s) has a DC value of
// x = 2d - 1, so e.g. d=0.875 (7 ones, 1 zero repeating) gives
// x = 0.75, expected pcm_out ~= 0.75 * 32,768 = 24,576 -- comfortably
// inside the signed 16-bit range, unlike d=1.0 (a constant rail, the
// one input this filter's bit growth is sized exactly to the edge of,
// deliberately not exercised here).
//
module tb_cic_decimator;

    reg clk, rst;
    reg pdm_sample_en, pdm_bit;
    wire signed [15:0] pcm_out;
    wire pcm_valid;

    integer errors = 0;
    integer checks = 0;

    cic_decimator #(.RATIO(64), .ACC_WIDTH(19), .OUT_WIDTH(16)) dut (
        .clk(clk), .rst(rst),
        .pdm_sample_en(pdm_sample_en), .pdm_bit(pdm_bit),
        .pcm_out(pcm_out), .pcm_valid(pcm_valid)
    );

    always #5 clk = ~clk; // 100 MHz

    // one PDM "tick" every 32 clk cycles, mirroring pdm_clk_gen's divide
    task pdm_bit_in(input bit_val);
        begin
            pdm_bit = bit_val;
            pdm_sample_en = 1'b1;
            @(posedge clk);
            pdm_sample_en = 1'b0;
            repeat (31) @(posedge clk);
        end
    endtask

    task check_range(input signed [15:0] got, input signed [15:0] lo,
                      input signed [15:0] hi, input [255:0] name);
        begin
            checks = checks + 1;
            if (got < lo || got > hi) begin
                errors = errors + 1;
                $display("FAIL %s: pcm_out=%0d expected in [%0d, %0d]", name, got, lo, hi);
            end else begin
                $display("pass %s: pcm_out=%0d in [%0d, %0d]", name, got, lo, hi);
            end
        end
    endtask

    integer i;
    reg signed [15:0] last_pcm;

    initial begin
        clk = 0; rst = 1; pdm_sample_en = 0; pdm_bit = 0;
        repeat (4) @(posedge clk);
        rst = 0;

        // --- balanced, alternating input: expect settling near zero ---
        for (i = 0; i < 64 * 10; i = i + 1)
            pdm_bit_in(i[0]);
        check_range(pcm_out, -16'sd2000, 16'sd2000, "balanced 50% duty settles near 0");

        // --- mostly-1 input (7 ones, 1 zero repeating, 87.5% duty) ---
        for (i = 0; i < 64 * 10; i = i + 1)
            pdm_bit_in((i % 8) != 7);
        check_range(pcm_out, 16'sd20000, 16'sd28000, "87.5% duty settles strongly positive");

        // --- mostly-0 input (mirror of the above, 12.5% duty) ---
        for (i = 0; i < 64 * 10; i = i + 1)
            pdm_bit_in((i % 8) == 7);
        check_range(pcm_out, -16'sd28000, -16'sd20000, "12.5% duty settles strongly negative");

        if (errors == 0)
            $display("ALL CHECKS PASSED (%0d checks)", checks);
        else
            $display("%0d of %0d CHECKS FAILED", errors, checks);

        $finish;
    end

endmodule
