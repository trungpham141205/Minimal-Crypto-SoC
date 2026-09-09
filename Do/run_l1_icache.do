# Run from the KLTN project root:
#   vsim -do Do/run_l1_icache.do

transcript on
onerror {quit -force -code 1}
onbreak {resume}

set project_root [pwd]
set run_dir [file join $project_root sim tb_l1_icache]
set lib_dir [file join $run_dir work]

file mkdir $run_dir
if {![file isdirectory $lib_dir]} {
    vlib $lib_dir
}

vmap work $lib_dir
vlog -sv -work work RV32I_Single_Cycle/l1_icache.sv
vlog -sv -work work TB/tb_l1_icache.sv

cd $run_dir
vsim -onfinish stop -voptargs=+acc -wlf tb_l1_icache.wlf work.tb_l1_icache

catch {add wave -divider "CPU SIDE"}
catch {add wave -hex sim:/tb_l1_icache/cpu_addr}
catch {add wave sim:/tb_l1_icache/cpu_req}
catch {add wave sim:/tb_l1_icache/cpu_valid}
catch {add wave -hex sim:/tb_l1_icache/cpu_instr}
catch {add wave sim:/tb_l1_icache/hit}
catch {add wave sim:/tb_l1_icache/miss}
catch {add wave sim:/tb_l1_icache/busy}

catch {add wave -divider "REFILL SIDE"}
catch {add wave -hex sim:/tb_l1_icache/mem_addr}
catch {add wave sim:/tb_l1_icache/mem_req}
catch {add wave sim:/tb_l1_icache/mem_valid}
catch {add wave -hex sim:/tb_l1_icache/mem_rdata}

catch {add wave -divider "CACHE INTERNAL"}
catch {add wave sim:/tb_l1_icache/dut/state_q}
catch {add wave -hex sim:/tb_l1_icache/dut/miss_line_base_q}
catch {add wave -unsigned sim:/tb_l1_icache/dut/miss_index_q}
catch {add wave -unsigned sim:/tb_l1_icache/dut/refill_word_q}
catch {add wave -unsigned sim:/tb_l1_icache/refill_transfer_count}
catch {add wave sim:/tb_l1_icache/invalidate_all}

run -all

set passed [examine -radix unsigned sim:/tb_l1_icache/test_passed]
if {$passed ne "1"} {
    puts "FAIL: tb_l1_icache did not complete its checks."
    quit -force -code 1
}

puts "PASS: tb_l1_icache"
