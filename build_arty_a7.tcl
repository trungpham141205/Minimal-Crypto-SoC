set root [file normalize [file dirname [info script]]]
set out [file join $root build arty_a7_100t]
set part xc7a100tcsg324-1

if {![file exists [file join $out instruction_memory.sv]]} {
    error "Run bash firmware/build_arty_a7.sh first."
}

set_param general.maxThreads 8
set files [open [file join $root filelist_soc.f] r]
while {[gets $files line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} { continue }
    if {$line eq "RV32I_Single_Cycle/instruction_memory.sv"} {
        read_verilog -sv [file join $out instruction_memory.sv]
    } elseif {$line ne "soc_top.sv"} {
        read_verilog -sv [file join $root $line]
    }
}
close $files
read_verilog -sv [file join $root soc_top.sv]
read_verilog -sv [file join $root arty_a7_top.sv]
read_xdc [file join $root arty_a7_100t.xdc]

synth_design -top arty_a7_top -part $part -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -file [file join $out timing_summary.rpt]
report_utilization -file [file join $out utilization.rpt]
report_clock_utilization -file [file join $out clocks.rpt]

set paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $paths] == 0} { error "No timed setup path; inspect constraints." }
set slack [get_property SLACK [lindex $paths 0]]
puts "Arty A7 routed setup worst slack: ${slack} ns at 47.619 MHz"
if {$slack < 0} { error "Routed timing failed; bitstream not written." }

write_checkpoint -force [file join $out arty_a7_100t_routed.dcp]
write_bitstream -force [file join $out arty_a7_100t.bit]
puts "Bitstream: [file join $out arty_a7_100t.bit]"
