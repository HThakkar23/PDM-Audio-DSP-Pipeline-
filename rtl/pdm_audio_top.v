`timescale 1ns / 1ps
//
// Top level: onboard PDM microphone in, CIC decimator, LED VU meter,
// delta-sigma modulator back out to the onboard speaker pin. Entirely
// standalone -- no host link, no UART, nothing to run on a PC -- the
// whole signal chain lives in the FPGA fabric and runs the moment the
// board is powered and out of reset.
//
// Single clock domain throughout: the mic's bit clock, the CIC's
// decimated sample clock, and the delta-sigma DAC's 100 MHz oversampled
// clock are all generated from (or simply run at) the one 100 MHz board
// oscillator, so there is no clock domain crossing anywhere in this
// design.
//
module pdm_audio_top (
    input  wire clk_in,          // 100 MHz onboard oscillator
    input  wire btn_rst,         // async reset button, active high

    output wire pdm_mic_clk,     // to the onboard PDM mic's clock pin
    input  wire pdm_mic_data,    // from the onboard PDM mic's data pin
    output wire audio_out,       // to the onboard speaker pin

    output wire [9:0] led
);

    wire clk = clk_in;
    wire rst;

    reset_sync u_reset_sync (
        .clk          (clk),
        .async_rst_in (btn_rst),
        .sync_rst_out (rst)
    );

    // ---- PDM mic clock + bit-period tick ----
    wire pdm_tick;
    pdm_clk_gen #(.DIV_W(5)) u_pdm_clk_gen (
        .clk      (clk),
        .rst      (rst),
        .pdm_clk  (pdm_mic_clk),
        .pdm_tick (pdm_tick)
    );

    // 2-FF synchronizer for the mic's data pin, standard practice for
    // any off-chip input regardless of how it is clocked
    reg [1:0] pdm_data_sync;
    always @(posedge clk) begin
        if (rst)
            pdm_data_sync <= 2'b00;
        else
            pdm_data_sync <= {pdm_data_sync[0], pdm_mic_data};
    end
    wire pdm_bit = pdm_data_sync[1];

    // ---- PDM -> PCM decimation ----
    wire signed [15:0] pcm;
    wire               pcm_valid;
    cic_decimator #(
        .RATIO     (64),
        .ACC_WIDTH (19),
        .OUT_WIDTH (16)
    ) u_cic (
        .clk           (clk),
        .rst           (rst),
        .pdm_sample_en (pdm_tick),
        .pdm_bit       (pdm_bit),
        .pcm_out       (pcm),
        .pcm_valid     (pcm_valid)
    );

    // ---- LED VU meter ----
    wire [7:0] vu_bar;
    wire       vu_clip;
    vu_meter #(
        .IN_WIDTH    (16),
        .DECAY_SHIFT (6)
    ) u_vu_meter (
        .clk       (clk),
        .rst       (rst),
        .pcm_in    (pcm),
        .pcm_valid (pcm_valid),
        .bar       (vu_bar),
        .clip      (vu_clip)
    );

    // ---- PCM -> 1-bit delta-sigma speaker drive ----
    // pcm itself is already a zero-order-hold register (only updates
    // once per decimated sample), so it is exactly the held input this
    // modulator is meant to oversample at the full 100 MHz clock.
    delta_sigma_dac #(
        .IN_WIDTH  (16),
        .ACC_WIDTH (18)
    ) u_dac (
        .clk     (clk),
        .rst     (rst),
        .pcm_in  (pcm),
        .dac_out (audio_out)
    );

    // ---- heartbeat, ~1 Hz on led[0] ----
    reg [25:0] hb_cnt;
    reg        hb;
    always @(posedge clk) begin
        if (rst) begin
            hb_cnt <= 26'd0;
            hb     <= 1'b0;
        end else if (hb_cnt == 26'd49_999_999) begin
            hb_cnt <= 26'd0;
            hb     <= ~hb;
        end else begin
            hb_cnt <= hb_cnt + 1'b1;
        end
    end

    assign led[0]   = hb;
    assign led[1]   = vu_clip;
    assign led[9:2] = vu_bar;

endmodule
