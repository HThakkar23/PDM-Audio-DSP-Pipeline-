# Pin and timing constraints for the Real Digital Blackboard (Zynq-7000,
# XC7Z007S-1CLG400C).
#
# Every pin below was checked directly against Real Digital's own vendor
# XDC, RealDigitalOrg/Blackboard, file master_xdc/master_revB.xdc
# (github.com/RealDigitalOrg/Blackboard, BSD-3-Clause) -- the primary
# source, not a third party's reading of it. That file confirms:
#   - clk_in/btn_rst/led[0..9] are the exact same physical pins the other
#     two projects in this portfolio already use (cross-checked pin for
#     pin against that file; see PDM mic note below for the one place
#     this project reads it differently).
#   - the onboard microphone is a PDM device (SPK0833LM4H per Real
#     Digital's Blackboard user manual), wired to exactly two pins
#     (PDM_MIC_CLK, PDM_MIC_DATA), not an I2S/I2C codec.
#   - the onboard speaker is a single pin ("audio"), documented as
#     accepting either PWM or PDM drive -- this project drives it with a
#     delta-sigma modulated bitstream, a form of PDM.
#
# IOSTANDARD for the three audio pins (PDM_MIC_CLK, PDM_MIC_DATA, audio)
# is assumed LVCMOS33 to match every other confirmed pin on this board;
# master_revB.xdc's lines for these three specific pins were read without
# their IOSTANDARD property, so this one assumption is worth a quick
# double check against the live file before building, unlike every other
# pin here which was checked and matched exactly.

## Clock, 100 MHz board oscillator
set_property PACKAGE_PIN H16 [get_ports clk_in]
set_property IOSTANDARD LVCMOS33 [get_ports clk_in]
create_clock -period 10.000 -name clk_in -waveform {0.000 5.000} [get_ports clk_in]

## Reset button, BTN3 on the silkscreen (btn[3] in Real Digital's own
## naming; repurposed as the single reset input, matching the other two
## Blackboard projects in this portfolio)
set_property PACKAGE_PIN M14 [get_ports btn_rst]
set_property IOSTANDARD LVCMOS33 [get_ports btn_rst]

## LEDs, LD0 through LD9 (LD4/LD5 are physically single channels of two
## RGB LEDs on this board revision; driving one channel of each as a
## plain on/off bit, as done here and in the other two projects, is
## electrically valid)
set_property PACKAGE_PIN N20 [get_ports {led[0]}]
set_property PACKAGE_PIN P20 [get_ports {led[1]}]
set_property PACKAGE_PIN R19 [get_ports {led[2]}]
set_property PACKAGE_PIN T20 [get_ports {led[3]}]
set_property PACKAGE_PIN T19 [get_ports {led[4]}]
set_property PACKAGE_PIN U13 [get_ports {led[5]}]
set_property PACKAGE_PIN V20 [get_ports {led[6]}]
set_property PACKAGE_PIN W20 [get_ports {led[7]}]
set_property PACKAGE_PIN W19 [get_ports {led[8]}]
set_property PACKAGE_PIN Y19 [get_ports {led[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## Onboard PDM microphone (SPK0833LM4H)
set_property PACKAGE_PIN L14 [get_ports pdm_mic_clk]
set_property PACKAGE_PIN N15 [get_ports pdm_mic_data]
set_property IOSTANDARD LVCMOS33 [get_ports pdm_mic_clk]
set_property IOSTANDARD LVCMOS33 [get_ports pdm_mic_data]

## Onboard speaker, single pin, PWM/PDM drive
set_property PACKAGE_PIN G18 [get_ports audio_out]
set_property IOSTANDARD LVCMOS33 [get_ports audio_out]

## Config options, standard for this part
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
