#!/usr/bin/env python
"""
Derives the real numbers behind cic_decimator.v:

  1. The Hogenauer (1981) register-growth bound that sets ACC_WIDTH.
  2. The PDM bit clock and decimated PCM sample rate pdm_clk_gen.v and
     cic_decimator.v actually produce, from the board's 100 MHz oscillator.
  3. The filter's step-response latency -- NOT hand-traced this time, but
     measured by running a cycle-accurate Python re-implementation of
     cic_decimator.v's exact register transfer logic (same nonblocking-
     assignment update order, same bit widths and wraparound) and timing
     how many PDM bit periods / clk cycles it actually takes to respond
     to and settle after a step input.
  4. The CIC's sinc^3 passband droop at a couple of reference audio
     frequencies, from the closed-form CIC magnitude response.

Run directly: `python scripts/cic_filter_calc.py`
"""

import math

# ---------------------------------------------------------------------
# 1. Hogenauer register growth
# ---------------------------------------------------------------------
N = 3          # CIC order (3 integrators, 3 combs)
R = 64         # decimation ratio
IN_WIDTH = 1   # PDM input is a single +-1 bit

growth_bits = math.ceil(N * math.log2(R))
ACC_WIDTH = IN_WIDTH + growth_bits
OUT_WIDTH = 16

print("=== 1. Hogenauer register growth ===")
print(f"  N (order) = {N}, R (decimation) = {R}, log2(R) = {math.log2(R):.4f}")
print(f"  growth = ceil(N * log2(R)) = ceil({N} * {math.log2(R):.4f}) = {growth_bits} bits")
print(f"  ACC_WIDTH = {IN_WIDTH} (input) + {growth_bits} (growth) = {ACC_WIDTH} bits  "
      f"(matches cic_decimator.v's ACC_WIDTH={ACC_WIDTH})")
print()

# ---------------------------------------------------------------------
# 2. Clock / sample rates
# ---------------------------------------------------------------------
F_CLK = 100_000_000       # board oscillator
DIV_W = 5                 # pdm_clk_gen.v divider width -> divide by 2^DIV_W
PDM_DIV = 2 ** DIV_W

f_pdm = F_CLK / PDM_DIV
f_out = f_pdm / R

print("=== 2. Clock / sample rates ===")
print(f"  f_clk            = {F_CLK:,} Hz")
print(f"  PDM bit clock    = f_clk / {PDM_DIV} = {f_pdm:,.3f} Hz")
print(f"  decimated f_out  = f_pdm / {R} = {f_out:,.4f} Hz")
print(f"  output Nyquist   = f_out / 2 = {f_out/2:,.4f} Hz")
print()


# ---------------------------------------------------------------------
# 3. Cycle-accurate model of cic_decimator.v, to MEASURE step latency
# ---------------------------------------------------------------------
def wrap_signed(val, width):
    mask = (1 << width) - 1
    val &= mask
    if val & (1 << (width - 1)):
        val -= 1 << width
    return val


class CicModel:
    """Exact re-implementation of cic_decimator.v's two always blocks.
    Every right-hand side below reads the OLD (pre-edge) value of every
    register, mirroring Verilog's nonblocking (<=) semantics -- the same
    rule that makes the RTL's comb stage read last cycle's comb3 for
    pcm_out while computing this cycle's new comb3."""

    def __init__(self, acc_width=ACC_WIDTH, out_width=OUT_WIDTH, ratio=R):
        self.acc_width = acc_width
        self.out_width = out_width
        self.ratio = ratio
        self.int1 = self.int2 = self.int3 = 0
        self.dec_cnt = 0
        self.x0 = self.x0_prev = 0
        self.comb1 = self.comb1_prev = 0
        self.comb2 = self.comb2_prev = 0
        self.comb3 = 0
        self.pcm_out = 0
        self.pcm_valid = False

    def tick(self, pdm_bit):
        w = self.acc_width
        pdm_signed = 1 if pdm_bit else -1

        dec_en = (self.dec_cnt == self.ratio - 1)

        new_int1 = wrap_signed(self.int1 + pdm_signed, w)
        new_int2 = wrap_signed(self.int2 + self.int1, w)
        new_int3 = wrap_signed(self.int3 + self.int2, w)
        new_dec_cnt = 0 if dec_en else (self.dec_cnt + 1)

        if dec_en:
            new_x0 = self.int3
            new_x0_prev = self.x0
            new_comb1 = wrap_signed(self.x0 - self.x0_prev, w)
            new_comb1_prev = self.comb1
            new_comb2 = wrap_signed(self.comb1 - self.comb1_prev, w)
            new_comb2_prev = self.comb2
            new_comb3 = wrap_signed(self.comb2 - self.comb2_prev, w)
            shifted = self.comb3 >> (w - self.out_width)   # arithmetic shift, old comb3
            new_pcm_out = wrap_signed(shifted, self.out_width)
            new_pcm_valid = True
        else:
            new_x0, new_x0_prev = self.x0, self.x0_prev
            new_comb1, new_comb1_prev = self.comb1, self.comb1_prev
            new_comb2, new_comb2_prev = self.comb2, self.comb2_prev
            new_comb3 = self.comb3
            new_pcm_out = self.pcm_out
            new_pcm_valid = False

        (self.int1, self.int2, self.int3, self.dec_cnt,
         self.x0, self.x0_prev, self.comb1, self.comb1_prev,
         self.comb2, self.comb2_prev, self.comb3,
         self.pcm_out, self.pcm_valid) = (
            new_int1, new_int2, new_int3, new_dec_cnt,
            new_x0, new_x0_prev, new_comb1, new_comb1_prev,
            new_comb2, new_comb2_prev, new_comb3,
            new_pcm_out, new_pcm_valid)

        return self.pcm_valid, self.pcm_out


print("=== 3. Step-response latency (measured, not hand-traced) ===")
print("  Driven with the same 12.5%/87.5% duty patterns tb_cic_decimator.v")
print("  checks (bipolar DC of -0.75 / +0.75), not a literal all-1s/all-0s")
print("  input -- see section 5 below for why that exact edge case is")
print("  deliberately avoided here, same as in the testbench.")
print()

PRE_SETTLE_TICKS = 2000   # run long enough to clear the reset transient
LOW_PATTERN  = [1 if (i % 8) == 7 else 0 for i in range(8)]   # 12.5% duty, DC = -0.75
HIGH_PATTERN = [1 if (i % 8) != 7 else 0 for i in range(8)]   # 87.5% duty, DC = +0.75


def drive_pattern(model, pattern, n_ticks):
    i = 0
    last = (None, None)
    for t in range(n_ticks):
        valid, pcm = model.tick(pattern[i % len(pattern)])
        i += 1
        if valid:
            last = (t + 1, pcm)
    return last


model = CicModel()
for i in range(PRE_SETTLE_TICKS):
    model.tick(LOW_PATTERN[i % len(LOW_PATTERN)])
_, baseline = drive_pattern(model, LOW_PATTERN, R * 4)

first_change_tick = None
settle_tick = None
samples_after_step = []
MAX_TICKS = R * 20
tick = 0
i = 0
while tick < MAX_TICKS:
    valid, pcm = model.tick(HIGH_PATTERN[i % len(HIGH_PATTERN)])
    i += 1
    tick += 1
    if valid:
        samples_after_step.append((tick, pcm))
        if pcm != baseline and first_change_tick is None:
            first_change_tick = tick
        if (len(samples_after_step) >= 3 and first_change_tick is not None and
                settle_tick is None and
                samples_after_step[-1][1] == samples_after_step[-2][1] == samples_after_step[-3][1]):
            settle_tick = samples_after_step[-3][0]
            break

final_value = samples_after_step[-1][1]

print(f"  baseline pcm_out (12.5% duty, DC=-0.75) = {baseline}")
print(f"  final pcm_out    (87.5% duty, DC=+0.75) = {final_value}")
print(f"  first decimated sample to change: tick {first_change_tick} "
      f"({first_change_tick} PDM bit periods = {first_change_tick * PDM_DIV} clk cycles "
      f"= {first_change_tick * PDM_DIV / F_CLK * 1e6:.3f} us)")
print(f"  fully settled by:                 tick {settle_tick} "
      f"({settle_tick} PDM bit periods = {settle_tick * PDM_DIV} clk cycles "
      f"= {settle_tick * PDM_DIV / F_CLK * 1e6:.3f} us)")

# classical CIC group-delay approximation, for a sanity cross-check only
classical_group_delay = N * (R - 1) / 2
print(f"  (classical CIC group-delay approximation N*(R-1)/2 = "
      f"{classical_group_delay:.1f} PDM bit periods -- a smaller, textbook "
      f"estimate of the filter's average delay, not its full settling time)")
print()

# ---------------------------------------------------------------------
# 4. Passband droop, closed-form CIC magnitude response
# ---------------------------------------------------------------------
def cic_mag_db(f_hz, fs_in_hz, order, ratio):
    """|H(f)| for a sinc^N CIC filter, normalized to 0 dB at DC."""
    x = math.pi * f_hz / fs_in_hz
    num = math.sin(ratio * x)
    den = ratio * math.sin(x)
    mag = abs(num / den) ** order
    return 20 * math.log10(mag)


print("=== 4. Passband droop (sinc^3 response, relative to DC) ===")
for f_ref, label in [(300, "300 Hz (telephone band low edge)"),
                      (3400, "3,400 Hz (telephone band high edge)"),
                      (8000, "8,000 Hz (wideband speech edge)"),
                      (f_out / 2, "output Nyquist")]:
    db = cic_mag_db(f_ref, f_pdm, N, R)
    print(f"  {label:38s}: {db:+7.3f} dB")
print()

print("=== 5. Full-scale edge case: 2's-complement wraparound, confirmed ===")
print("  cic_decimator.v deliberately does not saturate -- ACC_WIDTH is sized")
print("  so wraparound in the integrators is harmless for any input *except*")
print("  a literal, sustained all-1s or all-0s bitstream, where the ideal")
print("  output (+-32,768) itself does not fit in signed 16-bit (-32,768..")
print("  +32,767) and wraps. Confirmed here by actually driving the model")
print("  with a sustained constant stream of 1s after it settles on 0s:")

edge_model = CicModel()
for _ in range(2000):
    edge_model.tick(0)
_, edge_baseline = drive_pattern(edge_model, [0], R * 4)
_, edge_final = drive_pattern(edge_model, [1], R * 10)
print(f"    all-0s steady state : pcm_out = {edge_baseline} (expected -32768, exact)")
print(f"    all-1s steady state : pcm_out = {edge_final} (ideal +32768 does not fit "
      f"in [-32768, 32767] -> wraps to {edge_final})")
print("  Any real microphone signal is AC-coupled audio, never a sustained DC")
print("  rail, so this edge case does not affect normal operation; it is")
print("  flagged here, run and confirmed, rather than left as a hand-wave.")
print()

print("=== Summary (feeds README / resume numbers) ===")
print(f"  ACC_WIDTH                 = {ACC_WIDTH} bits (Hogenauer-derived)")
print(f"  PDM bit clock             = {f_pdm:,.0f} Hz")
print(f"  Decimated PCM sample rate = {f_out:,.3f} Hz")
print(f"  Measured step settling    = {settle_tick} PDM periods "
      f"= {settle_tick * PDM_DIV} clk cycles = {settle_tick * PDM_DIV / F_CLK * 1e6:.2f} us")
print(f"  Droop at 3.4 kHz          = {cic_mag_db(3400, f_pdm, N, R):+.3f} dB")
