# Run from project root: dc_shell -f lab/dc_synth.tcl
# Independent output per run; original sm2 scripts and results are not used.
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set REF [file normalize [file join $ROOT .. sm2 ref]]
if {[info exists ::env(T2_REF)]} {set REF [file normalize $::env(T2_REF)]}
set TOP transformer_top
set TAG [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set RUN [file join $ROOT lab_runs dc_$TAG]
if {[file exists $RUN]} {error "Run directory already exists: $RUN"}
file mkdir $RUN
cd $RUN
file mkdir reports outputs work
set_app_var search_path [concat [list [file join $REF db] [file join $ROOT rtl]] $search_path]
set LIB [file join $REF db sc_max.db]
if {![file exists $LIB]} {error "Missing library: $LIB; set T2_REF to sm2/ref"}
set_app_var target_library [list $LIB]
set_app_var link_library [concat [list *] $target_library [list dw_foundation.sldb]]
define_design_lib WORK -path ./work
set_svf outputs/transformer_top.svf
set RTL {}
foreach name {pe_array.v exp_lut.v softmax_unit.v transformer_top.v} {
    set path [file join $ROOT rtl $name]
    if {![file exists $path]} {error "Missing RTL: $path"}
    lappend RTL $path
}
analyze -format verilog $RTL
# Default synthesis scope: N=4,D=8,F=16,LANES=2. Record this in the report.
elaborate $TOP
current_design $TOP
link
redirect -tee -file reports/design_check.rpt {check_design}
set PERIOD 50.0
if {[info exists ::env(T2_PERIOD)]} {set PERIOD $::env(T2_PERIOD)}
create_clock -name core_clk -period $PERIOD [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks core_clk]
set_clock_transition 0.1 [get_clocks core_clk]
set DATA_IN [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay -max [expr $PERIOD*0.2] -clock core_clk $DATA_IN
set_input_delay -min 0.0 -clock core_clk $DATA_IN
set_input_transition 0.1 $DATA_IN
set_output_delay -max [expr $PERIOD*0.2] -clock core_clk [all_outputs]
set_output_delay -min 0.0 -clock core_clk [all_outputs]
# External reset release must be synchronized. Reset recovery/removal is excluded.
set_false_path -from [get_ports rst_n]
set_load 0.05 [all_outputs]
redirect -tee -file reports/units.rpt {report_units}
redirect -tee -file reports/clocks.rpt {report_clock}
redirect -tee -file reports/pre_timing_check.rpt {check_timing}
# No scan insertion: this baseline has no DFT specification.
compile_ultra -no_autoungroup
change_names -rules verilog -hierarchy
redirect -tee -file reports/post_design_check.rpt {check_design}
redirect -tee -file reports/timing_check.rpt {check_timing}
redirect -tee -file reports/area.rpt {report_area -hierarchy}
redirect -tee -file reports/timing_setup.rpt {report_timing -delay max -max_paths 10}
redirect -tee -file reports/timing_hold.rpt {report_timing -delay min -max_paths 10}
redirect -tee -file reports/constraints.rpt {report_constraint -all_violators}
redirect -tee -file reports/power.rpt {report_power}
redirect -tee -file reports/qor.rpt {report_qor}
write -format ddc -hierarchy -output outputs/transformer_top.mapped.ddc
write -format verilog -hierarchy -output outputs/transformer_top.mapped.v
write_sdc outputs/transformer_top.sdc
set_svf -off
set note [open run_scope.txt w]
puts $note "TOP=$TOP N=4 D=8 F=16 LANES=2 period=$PERIOD library=$LIB"
puts $note "Inspect units.rpt. Default intent: ns time, library capacitance unit for load=0.05."
puts $note "Vectorless power estimate; no activity file loaded. Reset recovery/removal excluded."
puts $note "No SRAM macro, scan insertion, or physical signoff. DC errors must be reviewed in full log."
close $note
puts "OUTPUT_DIRECTORY=$RUN"
exit
