# Builds the Vivado project for the PDM mic -> CIC -> VU meter / delta-sigma
# speaker audio DSP pipeline from scratch.
#
# Run this from the Vivado Tcl console with the project root as the
# current directory, for example:
#
#   cd C:/Users/hthakkar/Desktop/Hardware/pdm-audio-dsp
#   source scripts/create_project.tcl
#
# This creates the project, adds every RTL file and testbench, and adds
# the pin constraints. As with the other two Blackboard projects, there
# is no Clocking Wizard IP to generate: the mic clock divider, the CIC
# decimator and the delta-sigma modulator all run from the single
# 100 MHz board oscillator, so clk_in is used directly and there is no
# second clock domain to build. It stops short of running synthesis,
# implementation or bitstream generation so you can look over the
# project in the GUI first; the commands to run the rest of the flow in
# batch mode are at the bottom, commented out.

set proj_name "pdm_audio_dsp"
set proj_dir  "./build"
set part_name "xc7z007s-1clg400c-1"

create_project $proj_name $proj_dir -part $part_name -force

set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

# RTL sources
add_files -norecurse {
    rtl/reset_sync.v
    rtl/pdm_clk_gen.v
    rtl/cic_decimator.v
    rtl/vu_meter.v
    rtl/delta_sigma_dac.v
    rtl/pdm_audio_top.v
}

# Testbenches, simulation only
add_files -fileset sim_1 -norecurse {
    sim/tb_cic_decimator.v
    sim/tb_delta_sigma_dac.v
}

# Constraints
add_files -fileset constrs_1 -norecurse constr/blackboard_pdm.xdc

set_property top pdm_audio_top [current_fileset]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created at $proj_dir. Open $proj_dir/$proj_name.xpr in Vivado,"
puts "or keep working from this Tcl console."

# --- Optional: full batch build ---
# Uncomment these lines to run synthesis, implementation and bitstream
# generation without opening the GUI at all.
#
# launch_runs synth_1 -jobs 4
# wait_on_run synth_1
# launch_runs impl_1 -to_step write_bitstream -jobs 4
# wait_on_run impl_1
# puts "Bitstream at $proj_dir/$proj_name.runs/impl_1/pdm_audio_top.bit"
