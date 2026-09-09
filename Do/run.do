# Run from /home/trungpham/PROJECT/KLTN:
#   vsim -do Do/run.do
# Batch:
#   vsim -c -do "do Do/run.do; quit -force"
# Firmware: firmware/program_smoke_backup.hex
# Outputs: sim/tb_soc_top/

do Do/soc_common.do
onerror {quit -force -code 1}
onbreak {resume}
soc_prepare tb_soc_top firmware/program_smoke_backup.hex

quietly catch {add wave -noupdate -divider "CLOCK / RESET"}
quietly catch {add wave -noupdate sim:/tb_soc_top/clk}
quietly catch {add wave -noupdate sim:/tb_soc_top/rstn}
quietly catch {add wave -noupdate sim:/tb_soc_top/cpu_stall_debug}
quietly catch {add wave -noupdate sim:/tb_soc_top/aes_done_debug}
quietly catch {add wave -noupdate sim:/tb_soc_top/uart_tx_o}
quietly catch {add wave -noupdate sim:/tb_soc_top/uart_rx_i}

quietly catch {add wave -noupdate -divider "CPU"}
quietly catch {add wave -hex sim:/tb_soc_top/dut/u_cpu/pc_debug}
quietly catch {add wave -hex sim:/tb_soc_top/dut/u_cpu/instr_debug}
quietly catch {add wave -hex sim:/tb_soc_top/dut/cpu_mem_addr}
quietly catch {add wave -hex sim:/tb_soc_top/dut/cpu_mem_wdata}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_mem_read}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_mem_write}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_mem_stall}
quietly catch {add wave -hex sim:/tb_soc_top/dut/cpu_mem_rdata}

quietly catch {add wave -noupdate -divider "CPU AXI WRITE"}
quietly catch {add wave -hex sim:/tb_soc_top/dut/cpu_axi/awaddr}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/awvalid}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/awready}
quietly catch {add wave -hex sim:/tb_soc_top/dut/cpu_axi/wdata}
quietly catch {add wave -binary sim:/tb_soc_top/dut/cpu_axi/wstrb}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/wvalid}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/wready}
quietly catch {add wave -binary sim:/tb_soc_top/dut/cpu_axi/bresp}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/bvalid}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/bready}

quietly catch {add wave -noupdate -divider "CPU AXI READ"}
quietly catch {add wave -hex sim:/tb_soc_top/dut/cpu_axi/araddr}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/arvalid}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/arready}
quietly catch {add wave -hex sim:/tb_soc_top/dut/cpu_axi/rdata}
quietly catch {add wave -binary sim:/tb_soc_top/dut/cpu_axi/rresp}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/rvalid}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/cpu_axi/rready}

quietly catch {add wave -noupdate -divider "AES"}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/u_aes_slave/busy_q}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/u_aes_slave/done_q}
quietly catch {add wave -hex sim:/tb_soc_top/dut/u_aes_slave/aes_plain_text}
quietly catch {add wave -hex sim:/tb_soc_top/dut/u_aes_slave/aes_cipher_key}
quietly catch {add wave -hex sim:/tb_soc_top/dut/u_aes_slave/aes_cipher_text}

quietly catch {add wave -noupdate -divider "UART"}
quietly catch {add wave -hex sim:/tb_soc_top/dut/u_uart_slave/tx_data_q}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/u_uart_slave/tx_pending_q}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/u_uart_slave/uart_tx_ready}
quietly catch {add wave -noupdate sim:/tb_soc_top/dut/uart_tx_o}


soc_sram_waves tb_soc_top
catch {update}
soc_run tb_soc_top
