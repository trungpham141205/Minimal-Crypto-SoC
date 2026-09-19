# Signals relevant to the corrupted-checksum rejection test, then run.
#   xsim tb_soc_uart_boot_bad_checksum_snap --gui --tclbatch Do/wave_uart_boot_bad_checksum.tcl

set tb /tb_soc_uart_boot_bad_checksum

# UART boot pins
add_wave $tb/uart_rx_i
add_wave $tb/uart_tx_o

# CPU execution
add_wave -radix hex $tb/dut/u_cpu/pc_debug
add_wave -radix hex $tb/dut/u_cpu/instr_debug
add_wave $tb/dut/cpu_stall_debug

# Instruction SRAM load (payload still gets written before checksum check)
add_wave -radix hex $tb/dut/instr_sram_axi/awaddr
add_wave $tb/dut/instr_sram_axi/awvalid
add_wave $tb/dut/instr_sram_axi/awready
add_wave -radix hex $tb/dut/instr_sram_axi/wdata
add_wave $tb/dut/instr_sram_axi/wvalid
add_wave $tb/dut/instr_sram_axi/wready
add_wave $tb/dut/instr_sram_axi/bvalid
add_wave $tb/dut/instr_sram_axi/bready

# Testbench bookkeeping (proves the error path never reaches AES)
add_wave $tb/pc_entered_instr_region
add_wave -radix hex $tb/shared_ct_write_seen

run all
