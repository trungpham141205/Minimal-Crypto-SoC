set root [file normalize [file dirname [info script]]]
set bitstream [file join $root build arty_a7_100t arty_a7_100t.bit]
if {[llength $argv] > 0} { set bitstream [file normalize [lindex $argv 0]] }
if {![file exists $bitstream]} { error "Bitstream missing: $bitstream" }

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set devices [get_hw_devices -filter {PART == "xc7a100t"}]
if {[llength $devices] != 1} {
    error "Expected one xc7a100t device; found [llength $devices]: $devices"
}
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
puts "Programmed $device with $bitstream"
close_hw_manager
