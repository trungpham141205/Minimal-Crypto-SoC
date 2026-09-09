# Run from /home/trungpham/PROJECT/KLTN:
#   vsim -do Do/run_sram_copy.do
# Batch:
#   vsim -c -do "do Do/run_sram_copy.do; quit -force"
# Firmware: firmware/program_sram_copy.hex
# Outputs: sim/tb_soc_sram_copy/

do Do/soc_common.do
onerror {quit -force -code 1}
onbreak {resume}
soc_prepare tb_soc_sram_copy firmware/program_sram_copy.hex

catch {add wave -divider "CPU"}
catch {add wave -hex sim:/tb_soc_sram_copy/dut/u_cpu/pc_debug}
catch {add wave -hex sim:/tb_soc_sram_copy/dut/u_cpu/instr_debug}
catch {add wave sim:/tb_soc_sram_copy/cpu_stall_debug}
catch {add wave -hex sim:/tb_soc_sram_copy/dut/cpu_mem_addr}
catch {add wave -hex sim:/tb_soc_sram_copy/dut/cpu_mem_wdata}
catch {add wave -hex sim:/tb_soc_sram_copy/dut/cpu_mem_rdata}

catch {add wave -divider "INTERCONNECT"}
catch {add wave sim:/tb_soc_sram_copy/dut/u_interconnect/wr_sel_q}
catch {add wave sim:/tb_soc_sram_copy/dut/u_interconnect/rd_sel_q}
catch {add wave sim:/tb_soc_sram_copy/dut/u_interconnect/wr_active_q}
catch {add wave sim:/tb_soc_sram_copy/dut/u_interconnect/rd_active_q}

soc_sram_waves tb_soc_sram_copy
catch {update}
soc_run tb_soc_sram_copy
