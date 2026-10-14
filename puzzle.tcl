# This is a tcl command script for the Vivado tool chain.
# The board name, the FPGA part, the top level module, the number of threads,
# and the VHDL source files are given as arguments (-tclargs), so this
# information is only in the Makefile. Use "make mega65-r3", "make mega65-r6",
# or "make nexys4ddr". The Makefile runs Vivado in build/<board>, so the output
# files (<board>.dcp, <board>.bit, logs, etc.) are written there. The
# constraint file (<board>.xdc) is next to this script.
#
# The reports of the routed design (timing.rpt, utilization.rpt, and
# power.rpt) are written to build/<board> too. The bit-file is only written
# when the design meets timing (setup and hold). Otherwise any old bit-file
# is deleted, and the script stops with an error, so "make fpga" can not
# load a design that fails timing. The routed checkpoint is still written,
# so the failing paths can be examined.
if {[llength $argv] < 5} {
   puts "ERROR: No board and source files given. Use \"make mega65-r3\", \"make mega65-r6\", or \"make nexys4ddr\"."
   exit 1
}
lassign $argv board part top threads
set script_dir [file dirname [file normalize [info script]]]
set_param general.maxThreads $threads
foreach src [lrange $argv 4 end] {
   read_vhdl -vhdl2008 $src
}
read_xdc [file join $script_dir $board.xdc]
set_param messaging.defaultLimit 3000
synth_design -top $top -part $part -flatten_hierarchy rebuilt
report_utilization -file utilization_synth.rpt
opt_design
# The default directives: the stronger ones (ExtraTimingOpt, and
# AggressiveExplore twice) made the MEGA65 build take 30 minutes. The
# optimization after routing is only done if it is needed.
place_design
phys_opt_design
route_design
if {[get_property SLACK [get_timing_paths -delay_type max]] < 0} {
   phys_opt_design -directive AggressiveExplore
}
write_checkpoint -force $board.dcp
report_timing_summary -file timing.rpt
report_utilization -file utilization.rpt
report_utilization -hierarchical -hierarchical_depth 6 -file utilization_hier.rpt
report_power -file power.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "INFO: Setup slack (WNS) $wns ns, hold slack (WHS) $whs ns."
if {$wns < 0 || $whs < 0} {
   file delete -force $board.bit
   puts "ERROR: The design does not meet timing (WNS $wns ns, WHS $whs ns), so no bit-file is written. See timing.rpt."
   exit 1
}
write_bitstream -force $board.bit
exit
