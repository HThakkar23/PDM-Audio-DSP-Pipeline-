# Setup guide

This walks through building the project in Vivado and getting it running
on a Real Digital Blackboard. It assumes Vivado is already installed
(2019.2 or newer should work fine; this was written against the Zynq-7000
support in current Vivado releases) and that you have the board, a
powered speaker or headphone amp on the "audio" pin if you want to hear
anything (the board drives a single raw digital pin, not a line-level
output), and nothing else. There is no host-side software for this
project at all -- no USB cable, no serial adapter, no Python client. The
whole signal chain runs standalone in the FPGA fabric the moment the
board is powered and out of reset.

## 1. Check the pin constraints first

Open `constr/blackboard_pdm.xdc`. Every pin in it was checked directly
against Real Digital's own vendor XDC
(`RealDigitalOrg/Blackboard`, `master_xdc/master_revB.xdc`), the most
authoritative pin source available, rather than a third party's reading
of it -- and cross-checked against the pin file the other two projects
in this portfolio already use, which it matches exactly on every shared
pin (clock, reset, all 10 LEDs). One thing is still worth a quick,
optional double check:

- **PDM mic / speaker IOSTANDARD.** `pdm_mic_clk`, `pdm_mic_data` and
  `audio_out` are set to LVCMOS33 here, matching every other confirmed
  pin on this board. The vendor file's lines for these three specific
  pins were read without their IOSTANDARD property attached, so if you
  have Vivado's board file or the raw XDC open, a quick glance confirms
  it; nothing else here should need changing.

## 2. Build the project

Open Vivado, go to the Tcl console, and run:

```
cd C:/Users/hthakkar/Desktop/Hardware/pdm-audio-dsp
source scripts/create_project.tcl
```

This creates a project under `build/`, adds all the RTL files, the
testbenches, and the constraints file. As with the other two Blackboard
projects, there is no Clocking Wizard IP to generate: the mic clock
divider, the CIC decimator, and the delta-sigma modulator all run from
the single 100 MHz board oscillator. The script stops before synthesis
so you can look at the project first; the bottom of the script has
commented out lines that run synthesis, implementation and bitstream
generation in one go if you would rather skip the GUI.

If you prefer to build everything by hand through the GUI instead of
running the script, the steps are:

1. File, New Project. Pick the Real Digital Blackboard board file if you
   have it installed, otherwise select part `xc7z007s-1clg400c-1` directly.
2. Add all files under `rtl/` as design sources.
3. Add the two files under `sim/` as simulation sources only.
4. Add `constr/blackboard_pdm.xdc` as a constraints source.
5. Set `pdm_audio_top` as the top module.

## 3. Run the simulations (optional, needs a simulator)

This machine does not have a simulator installed, so both testbenches
under `sim/` were written and checked by hand but never actually run
here. Once you have Vivado or another simulator available:

In Vivado, open the Simulation Sources fileset, right click on whichever
of `tb_cic_decimator` or `tb_delta_sigma_dac` you want to run, and set
it as the simulation top, then run behavioral simulation. Each
testbench prints `ALL CHECKS PASSED` or a failure count to the Tcl
console.

With a standalone Icarus Verilog install instead, from the project root:

```
iverilog -o sim_cic.out rtl/cic_decimator.v sim/tb_cic_decimator.v
vvp sim_cic.out

iverilog -o sim_dac.out rtl/delta_sigma_dac.v sim/tb_delta_sigma_dac.v
vvp sim_dac.out
```

## 4. Synthesis, implementation, and the bitstream

From the Flow Navigator: Run Synthesis, then Run Implementation, then
Generate Bitstream. This is a small design with no block RAM and a
single clock domain, so a clean build finishes quickly and resource
usage is not a concern.

## 5. Program the board and use it

Open Hardware Manager, connect to the board over JTAG, and program the
device with the generated `.bit` file. There is nothing else to run: the
moment the design is loaded and out of reset,

- `led[0]` blinks roughly once a second (heartbeat, confirms the system
  clock is alive),
- `led[9:2]` form an 8-level VU meter bar that tracks the loudness of
  whatever the onboard PDM microphone is picking up, decaying smoothly
  rather than flickering sample to sample,
- `led[1]` lights when the input gets loud enough to be within about 2%
  of clipping,
- and the "audio" pin carries a 1-bit delta-sigma modulated stream of
  that same microphone signal, heavily oversampled at 100 MHz -- feed it
  into a speaker or headphone amp (through a simple RC low-pass if your
  amp does not already filter high frequency switching noise) to hear
  it directly.

Tap the board's case or talk near the microphone and watch the LED bar
react; that is the whole signal chain, mic to decimator to meter and
back out to the speaker pin, running entirely in fabric.

## LED reference

| LED | Meaning |
|---|---|
| `led[0]` | heartbeat, toggles at roughly 1 Hz |
| `led[1]` | clip flag, set when the envelope is within ~2% of full scale |
| `led[9:2]` | 8-level VU bar, thermometer coded, tracks peak-with-decay envelope |
