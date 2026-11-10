# PDM mic -> CIC decimator -> VU meter / delta-sigma speaker

A standalone audio DSP pipeline built in Verilog for the Real Digital
Blackboard (Zynq-7000, XC7Z007S): the onboard PDM microphone's raw 1-bit
oversampled bitstream is decimated into real 16-bit PCM audio by a
from-scratch CIC (cascaded integrator-comb) filter, that PCM drives an
8-level LED VU meter, and it is re-modulated by a from-scratch
delta-sigma DAC back out to the onboard speaker pin. No UART, no host
link, no PC software of any kind -- every bit of DSP here runs in FPGA
fabric the instant the board powers up.

This is the third project on this board, after an earlier UART-to-VGA
terminal and a logic analyzer, and after a UART-to-AXI4-Lite bridge.
Those three all centered on getting a host link's protocol exactly
right; this one deliberately drops the host link altogether and spends
its effort on signal processing instead, because the Blackboard, like
most dev boards in this class, has no dedicated audio codec IC on
it -- just a bare PDM microphone and a single raw speaker pin -- so
getting from one to real audio samples and back is itself the design
problem, not a vendor IP core away. Every number below comes from a
Python script in `scripts/`, run and checked by hand, not from guessing;
section 3 of `scripts/cic_filter_calc.py` even measures the filter's
step-response latency by running a cycle-accurate re-implementation of
the actual RTL's register transfer logic, rather than hand-tracing it.

## What it does

Program the board and the pipeline runs on its own:

```
PDM mic -> pdm_clk_gen -> 2-FF sync -> cic_decimator -> vu_meter -> led[9:2]/led[1]
                                              |
                                              v
                                       delta_sigma_dac -> audio_out (speaker pin)
```

Tap the board's case or talk near the microphone and the LED bar on
`led[9:2]` tracks the loudness in real time with a smooth peak-with-decay
response instead of flickering on every sample; `led[1]` lights when the
signal gets close to clipping. The same decimated PCM feeds a 1-bit
delta-sigma modulator running at the full 100 MHz clock, so the speaker
pin carries a heavily oversampled bitstream whose average directly
tracks the microphone's waveform -- a real, if small, 1-bit DAC, not a
simple PWM tone generator.

## Why a CIC filter and a delta-sigma modulator, not vendor IP

A PDM microphone's output is not audio samples; it is a single wire
toggling at a few megahertz whose *density* of 1s over time encodes the
waveform (pulse density modulation). Turning that into usable PCM needs
a decimation filter, and the CIC structure -- integrators at the fast
bit rate, combs at the slow decimated rate -- is the standard answer
because it needs no multiplier at all when the input is already a 1-bit
signal: every stage in `cic_decimator.v` is a plain adder or subtractor.
The design is sized directly from Hogenauer's 1981 register-growth
bound (`ceil(N*log2(R))` extra bits for an N-th order, R:1 CIC, derived
and checked in `scripts/cic_filter_calc.py`) and deliberately never
saturates any intermediate stage -- it relies on 2's-complement
wraparound canceling correctly in the final comb, which is exactly what
makes a CIC filter work without per-stage clipping logic (see "A design
detail worth knowing about" below for the one input where that
assumption meets its edge).

Driving the speaker pin back out has the mirror problem: there is no
DAC IC on this pin, only a bare digital output documented as accepting
PWM or PDM drive. A first-order error-feedback delta-sigma modulator
turns each 16-bit PCM sample into a 1-bit stream whose running average
tracks it, pushing quantization noise up out of the audio band by
oversampling -- the same noise-shaping principle real audio DACs use,
built here from a single adder, a comparator, and one feedback register
(`delta_sigma_dac.v`).

## Architecture

```
  onboard PDM mic (SPK0833LM4H)
        |  1-bit bitstream @ 3.125 MHz
        v
  pdm_clk_gen  (divides 100 MHz -> 3.125 MHz mic clock)
        |
        v
  2-FF synchronizer        (crosses the mic's async data pin safely)
        |
        v
  cic_decimator            (sinc^3, 64:1, 1-bit PDM -> signed 16-bit PCM)
        |            \
        v             \
  vu_meter               \
  (8-level LED bar,       \
   peak-with-decay,        v
   clip flag)         delta_sigma_dac   (16-bit PCM -> 1-bit, 100 MHz oversampled)
        |                       |
        v                       v
     led[9:1]              audio_out (speaker pin)
```

Single clock domain throughout, same as the UART-to-AXI4-Lite bridge:
the mic clock divider, the CIC decimator, and the delta-sigma modulator
all run from the single 100 MHz board oscillator, so there is no
Clocking Wizard IP and no clock domain crossing anywhere in this design
beyond the one 2-FF synchronizer the mic's asynchronous data pin needs.

### Module list

| File | Role |
|---|---|
| `pdm_clk_gen.v` | divides 100 MHz down to the PDM mic's 3.125 MHz bit clock |
| `cic_decimator.v` | sinc^3 CIC filter, 64:1 decimation, PDM bitstream to signed 16-bit PCM |
| `vu_meter.v` | peak-with-decay envelope follower, 8-level LED bar + clip flag |
| `delta_sigma_dac.v` | 1st-order error-feedback delta-sigma modulator, PCM to 1-bit speaker drive |
| `reset_sync.v` | clean reset release, reused unchanged from the other two projects |
| `pdm_audio_top.v` | top level, wires everything above together, plus the heartbeat LED |

## The numbers

These come straight out of `scripts/cic_filter_calc.py` and
`scripts/delta_sigma_calc.py`, which you can run yourself with a plain
Python install (no dependencies beyond the standard library).

**CIC decimator (`cic_filter_calc.py`).**

```
ACC_WIDTH (Hogenauer-derived)   : 19 bits       (ceil(3 * log2(64)) + 1 sign bit)
PDM bit clock                   : 3,125,000.000 Hz
Decimated PCM sample rate       : 48,828.125 Hz
Output Nyquist                  : 24,414.0625 Hz
```

Step-response latency, *measured* by running a cycle-accurate Python
model of the exact RTL (same register widths, same nonblocking-update
order) through a 12.5%/87.5% duty-cycle step, not hand-traced:

```
first decimated sample to change : 304 PDM bit periods =  9,728 clk cycles =  97.28 us
fully settled                    : 496 PDM bit periods = 15,872 clk cycles = 158.72 us
(classical CIC group-delay estimate N*(R-1)/2 = 94.5 PDM periods, for comparison only)
```

Passband droop (sinc^3 magnitude response, relative to DC):

```
   300 Hz (telephone band low edge)  :  -0.002 dB
 3,400 Hz (telephone band high edge) :  -0.208 dB
 8,000 Hz (wideband speech edge)     :  -1.161 dB
        output Nyquist               : -11.765 dB
```

Flat to within a fifth of a dB across the entire telephone voice band,
which is the relevant comparison for a microphone pipeline sized for
speech-range audio rather than full 20 kHz hi-fi.

**Delta-sigma DAC (`delta_sigma_calc.py`).**

```
Oversampling ratio (OSR)         : 2048   (100,000,000 Hz / 48,828.125 Hz, exact)
Theoretical in-band SNR          : 101.95 dB   (1st-order, 1-bit, standard noise-shaping formula)
Effective resolution (ENOB)      : 16.64 bits
```

```
  order | OSR=64  | OSR=256 | OSR=1024 | OSR=2048
      1 |  56.79 dB |  74.86 dB |  92.92 dB | 101.95 dB  <- this design
      2 |  85.19 dB | 115.30 dB | 145.40 dB | 160.45 dB
      3 | 112.83 dB | 154.98 dB | 197.12 dB | 218.20 dB
```

The 1st-order, 1-bit loop this design uses trades the extra ~58 dB a
2nd-order loop would buy at the same OSR for a single adder and
comparator with no stability compensation to design -- a deliberate
simplicity trade, not an oversight.

**VU meter decay.** `DECAY_SHIFT = 6` gives an envelope time constant of
64 decimated samples, 1.31 ms at the 48,828.125 Hz decimated rate --
fast enough to feel responsive, slow enough not to flicker on individual
samples.

## A design detail worth knowing about

`cic_decimator.v` never saturates: every integrator and comb stage is
left to wrap in 2's complement, which is what makes a CIC filter's math
work without per-stage clipping logic. That assumption has exactly one
edge, and `scripts/cic_filter_calc.py` (section 5) runs it directly
rather than leaving it as a hand-wave: a literal, sustained all-1s (or
all-0s) PDM bitstream is the one input whose ideal decimated output,
+-32,768, does not itself fit in the signed 16-bit range
(-32,768..+32,767) that `OUT_WIDTH` provides, so it silently wraps to
the opposite sign. Confirmed by the calc script: an all-0s steady state
settles at exactly -32,768, and a sustained all-1s input, chasing that
same ideal +32,768, wraps right back around to -32,768 instead of the
positive full-scale value one would expect. Real microphone audio is
AC-coupled and never a sustained DC rail, so this never triggers in
normal operation -- it is exactly the one input `tb_cic_decimator.v`'s
own header comment already flagged as deliberately not exercised, now
backed by an actual run rather than just a comment.

## Repository layout

```
rtl/        Verilog source for every module
sim/        self checking testbenches (see SETUP.md for how to run them)
scripts/    Python scripts that compute the numbers quoted above, and the Tcl build script
constr/     Vivado XDC pin and timing constraints
SETUP.md    step by step build and bring up instructions
```

There is no `host/` directory in this project, unlike the other two --
there is nothing for a PC to talk to here.

## Building it

See [SETUP.md](SETUP.md) for the full walkthrough, including the one
IOSTANDARD worth a quick double check against your specific board
revision before building, and what to expect the moment the board is
programmed (there is no host script to run afterward).

## Possible extensions

A few directions this could go if picked back up later: a 2nd-order
delta-sigma loop to use the ~58 dB of extra headroom the comparison
table above shows is on the table, at the cost of a stability analysis
a 1st-order loop does not need; a simple FIR equalizer after the CIC to
compensate its sinc^3 droop before it becomes audible at wider
bandwidths than the telephone band this was sized for; or routing the
decimated PCM out over the existing UART-to-AXI4-Lite bridge's register
file instead of (or alongside) the onboard speaker, to capture real
waveforms on a host for analysis.
