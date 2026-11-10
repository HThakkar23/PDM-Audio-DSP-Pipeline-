#!/usr/bin/env python
"""
Derives the real numbers behind delta_sigma_dac.v:

  1. The oversampling ratio (OSR) the design actually runs at, from the
     board's 100 MHz clock and the CIC's decimated sample rate.
  2. The theoretical in-band SNR and effective resolution (ENOB) for a
     1st-order, 1-bit error-feedback delta-sigma modulator at that OSR,
     from the standard closed-form noise-shaping SNR equation.
  3. A comparison table across modulator order and OSR, to show where
     this design's choice (1st order, OSR=2048) sits relative to the
     alternatives, and what headroom a higher-order loop would buy.
  4. vu_meter.v's envelope decay time constant at its chosen DECAY_SHIFT,
     from the same decimated sample rate.

Run directly: `python scripts/delta_sigma_calc.py`
"""

import math

F_CLK = 100_000_000
F_OUT = 48_828.125     # CIC decimated sample rate, from cic_filter_calc.py

print("=== 1. Oversampling ratio ===")
OSR = F_CLK / F_OUT
print(f"  OSR = f_clk / f_out = {F_CLK:,} / {F_OUT:,.3f} = {OSR:.4f}")
print(f"        ({F_CLK:,} = 2^? no, but {int(round(OSR))} is exact: "
      f"f_out = f_clk / 2048 by construction, since 2048 = 32 (PDM divider) * 64 (CIC ratio))")
OSR = round(OSR)
print(f"  OSR (exact) = {OSR}")
print()


def ds_snr_db(n_bits, order, osr):
    """Standard Lth-order delta-sigma in-band SNR (dB), full-scale sine input.
    SNR = 6.02*n_bits + 1.76 - 10*log10(pi^(2L) / (2L+1)) + (20L+10)*log10(OSR)
    """
    quant_term = 6.02 * n_bits + 1.76
    shaping_penalty = 10 * math.log10((math.pi ** (2 * order)) / (2 * order + 1))
    osr_gain = (20 * order + 10) * math.log10(osr)
    return quant_term - shaping_penalty + osr_gain


def enob(snr_db):
    return (snr_db - 1.76) / 6.02


print("=== 2. This design: 1st-order, 1-bit modulator at OSR =", OSR, "===")
N_BITS = 1
ORDER = 1
snr = ds_snr_db(N_BITS, ORDER, OSR)
print(f"  quantizer term        6.02*{N_BITS} + 1.76        = {6.02*N_BITS+1.76:.3f} dB")
print(f"  1st-order shaping term -10*log10(pi^2/3)        = "
      f"{-10*math.log10(math.pi**2/3):.3f} dB")
print(f"  OSR gain term          30*log10({OSR})            = {30*math.log10(OSR):.3f} dB")
print(f"  theoretical in-band SNR                          = {snr:.2f} dB")
print(f"  effective resolution  (SNR-1.76)/6.02            = {enob(snr):.2f} bits")
print()

print("=== 3. Order / OSR comparison table ===")
print(f"  {'order':>6} | " + " | ".join(f"OSR={o:>5}" for o in [64, 256, 1024, 2048]))
for order in (1, 2, 3):
    row = []
    for osr in (64, 256, 1024, 2048):
        row.append(f"{ds_snr_db(1, order, osr):7.2f} dB")
    print(f"  {order:>6} | " + " | ".join(row))
print()
print("  This design uses the top-left corner of the order=1 row (OSR=2048):")
print(f"  a 2nd-order loop at the same OSR would add "
      f"{ds_snr_db(1,2,OSR)-ds_snr_db(1,1,OSR):.1f} dB (not implemented here --")
print("  the 1-bit error-feedback 1st-order loop was chosen for its single")
print("  adder/comparator simplicity, with no stability compensation to design.")
print()

print("=== 4. vu_meter.v envelope decay time constant ===")
DECAY_SHIFT = 6
tau_samples = 2 ** DECAY_SHIFT
tau_seconds = tau_samples / F_OUT
print(f"  DECAY_SHIFT = {DECAY_SHIFT} -> leaks 1/{tau_samples} of the envelope per sample")
print(f"  time constant (tau) ~= {tau_samples} decimated samples = {tau_seconds*1000:.3f} ms")
print()

print("=== Summary (feeds README / resume numbers) ===")
print(f"  OSR                       = {OSR}")
print(f"  Theoretical in-band SNR   = {snr:.2f} dB")
print(f"  Effective resolution      = {enob(snr):.2f} bits")
print(f"  VU meter decay tau        = {tau_seconds*1000:.2f} ms")
