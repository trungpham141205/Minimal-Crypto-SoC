# Add only the signals relevant to the UART-boot -> I-cache -> AES-256 test,
# then run to completion. Usage:
#   xsim tb_soc_uart_boot_snap --gui --tclbatch Do/wave_uart_boot.tcl

set tb /tb_soc_uart_boot

# UART boot pins
add_wave $tb/uart_rx_i
add_wave $tb/uart_tx_o

# CPU execution
add_wave -radix hex $tb/dut/u_cpu/pc_debug
add_wave -radix hex $tb/dut/u_cpu/instr_debug
add_wave $tb/dut/cpu_stall_debug

# UART RX MMIO
add_wave -radix hex $tb/dut/u_uart_slave/uart_rx_data
add_wave $tb/dut/u_uart_slave/uart_rx_valid
add_wave $tb/dut/u_uart_slave/uart_rx_ready
add_wave -radix hex $tb/dut/u_uart_slave/tx_data_q
add_wave $tb/dut/u_uart_slave/tx_pending_q

# Instruction SRAM load
add_wave -radix hex $tb/dut/instr_sram_axi/awaddr
add_wave $tb/dut/instr_sram_axi/awvalid
add_wave $tb/dut/instr_sram_axi/awready
add_wave -radix hex $tb/dut/instr_sram_axi/wdata
add_wave $tb/dut/instr_sram_axi/wvalid
add_wave $tb/dut/instr_sram_axi/wready
add_wave $tb/dut/instr_sram_axi/bvalid
add_wave $tb/dut/instr_sram_axi/bready

# L1 I-cache
add_wave $tb/dut/icache_invalidate
add_wave $tb/dut/icache_hit
add_wave $tb/dut/icache_miss
add_wave $tb/dut/icache_busy
add_wave $tb/dut/u_l1_icache/state_q
add_wave -radix hex $tb/dut/u_l1_icache/miss_line_base_q
add_wave -radix unsigned $tb/dut/u_l1_icache/refill_word_q
add_wave -radix hex $tb/dut/axi_fetch_addr
add_wave $tb/dut/axi_fetch_req
add_wave $tb/dut/axi_fetch_valid

# AES-256 KAT
add_wave $tb/dut/u_aes_slave/busy_q
add_wave $tb/dut/u_aes_slave/done_q
add_wave -radix hex $tb/dut/u_aes_slave/pt_q
add_wave -radix hex $tb/dut/u_aes_slave/key_q
add_wave -radix hex $tb/dut/u_aes_slave/ct_q
add_wave -radix hex $tb/shared_ct_write_seen

run all
