`timescale 1ns / 1ps
//
// Self-checking testbench for delta_sigma_dac.v. Written and checked by
// hand; no simulator is installed on this machine, so this has never
// actually been run. For a constant input held over a long enough
// window, a first-order error-feedback modulator's output duty cycle
// should converge to (pcm_in / FULL_SCALE + 1) / 2 -- e.g. pcm_in=0
// gives 50% ones, pcm_in=+FULL_SCALE/2 gives 75%, pcm_in=-FULL_SCALE/2
// gives 25% -- which is exactly what each check below measures over a
// 4096-cycle window.
//
module tb_delta_sigma_dac;

    reg clk, rst;
    reg signed [15:0] pcm_in;
    wire dac_out;

    integer errors = 0;
    integer checks = 0;

    delta_sigma_dac #(.IN_WIDTH(16), .ACC_WIDTH(18)) dut (
        .clk(clk), .rst(rst), .pcm_in(pcm_in), .dac_out(dac_out)
    );

    always #5 clk = ~clk; // 100 MHz

    localparam WINDOW = 4096;

    task measure_duty(input signed [15:0] level, input real expected_pct,
                       input [255:0] name);
        integer n, ones;
        real got_pct;
        begin
            pcm_in = level;
            repeat (64) @(posedge clk); // let the modulator settle first
            ones = 0;
            for (n = 0; n < WINDOW; n = n + 1) begin
                @(posedge clk);
                if (dac_out) ones = ones + 1;
            end
            got_pct = (100.0 * ones) / WINDOW;
            checks = checks + 1;
            if (got_pct < expected_pct - 2.0 || got_pct > expected_pct + 2.0) begin
                errors = errors + 1;
                $display("FAIL %s: duty=%.2f%% expected ~%.2f%% +-2%%", name, got_pct, expected_pct);
            end else begin
                $display("pass %s: duty=%.2f%% expected ~%.2f%% +-2%%", name, got_pct, expected_pct);
            end
        end
    endtask

    initial begin
        clk = 0; rst = 1; pcm_in = 0;
        repeat (4) @(posedge clk);
        rst = 0;

        measure_duty(16'sd0,      50.0, "zero input -> 50% duty");
        measure_duty(16'sd16384,  75.0, "+half scale -> 75% duty");
        measure_duty(-16'sd16384, 25.0, "-half scale -> 25% duty");

        if (errors == 0)
            $display("ALL CHECKS PASSED (%0d checks)", checks);
        else
            $display("%0d of %0d CHECKS FAILED", errors, checks);

        $finish;
    end

endmodule
