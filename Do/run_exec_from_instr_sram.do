# Run from KLTN root:
#   vsim -do Do/run_exec_from_instr_sram.do
#
# Milestone:
#   Boot ROM -> stores program into instruction SRAM -> JALR 0x00010000
#   -> instruction fetch through AXI -> program writes/reads shared SRAM.

do Do/soc_common.do
onerror {quit -force -code 1}
onbreak {resume}
soc_prepare tb_soc_exec_from_instr_sram firmware/program_exec_from_instr_sram.hex

catch {add wave -divider "CPU FETCH"}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/u_cpu/pc_debug}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/u_cpu/instr_debug}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/u_cpu/instruction_hold_valid_q}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/cpu_fetch_addr}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_fetch_req}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_fetch_valid}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/cpu_fetch_instr}

catch {add wave -divider "L1 I-CACHE"}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/icache_hit}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/icache_miss}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/icache_busy}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/icache_invalidate}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/u_l1_icache/state_q}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/u_l1_icache/miss_line_base_q}
catch {add wave -unsigned sim:/tb_soc_exec_from_instr_sram/dut/u_l1_icache/miss_index_q}
catch {add wave -unsigned sim:/tb_soc_exec_from_instr_sram/dut/u_l1_icache/refill_word_q}

catch {add wave -divider "FETCH / DATA ARBITER"}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/u_cpu_axi_arbiter/owner_q}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/axi_fetch_req}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/axi_fetch_valid}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/axi_fetch_addr}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/axi_fetch_rdata}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_mem_read}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_mem_write}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_mem_stall}

catch {add wave -divider "UNIFIED AXI MASTER"}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/araddr}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/arvalid}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/arready}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/rdata}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/rvalid}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/rready}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/awaddr}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/awvalid}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/awready}
catch {add wave -hex sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/wdata}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/wvalid}
catch {add wave sim:/tb_soc_exec_from_instr_sram/dut/cpu_axi/wready}

soc_sram_waves tb_soc_exec_from_instr_sram
catch {update}
soc_run tb_soc_exec_from_instr_sram
