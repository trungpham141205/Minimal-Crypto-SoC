# Run from /home/trungpham/PROJECT/KLTN:
#   vsim -do Do/run_uart_runtime.do
# Batch:
#   vsim -c -do "do Do/run_uart_runtime.do; quit -force"
# Firmware: firmware/program.hex
# Outputs: sim/tb_soc_uart_runtime/

do Do/soc_common.do
onerror {quit -force -code 1}
onbreak {resume}
soc_prepare tb_soc_uart_runtime firmware/program.hex

quietly catch {add wave -divider "UART PINS"}
quietly catch {add wave sim:/tb_soc_uart_runtime/uart_rx_i}
quietly catch {add wave sim:/tb_soc_uart_runtime/uart_tx_o}

quietly catch {add wave -divider "CPU"}
quietly catch {add wave -hex sim:/tb_soc_uart_runtime/dut/u_cpu/pc_debug}
quietly catch {add wave -hex sim:/tb_soc_uart_runtime/dut/u_cpu/instr_debug}
quietly catch {add wave sim:/tb_soc_uart_runtime/cpu_stall_debug}

quietly catch {add wave -divider "UART INTERNAL"}
quietly catch {add wave -hex sim:/tb_soc_uart_runtime/dut/u_uart_slave/uart_rx_data}
quietly catch {add wave sim:/tb_soc_uart_runtime/dut/u_uart_slave/uart_rx_valid}
quietly catch {add wave -hex sim:/tb_soc_uart_runtime/dut/u_uart_slave/tx_data_q}
quietly catch {add wave sim:/tb_soc_uart_runtime/dut/u_uart_slave/tx_pending_q}
quietly catch {add wave sim:/tb_soc_uart_runtime/dut/u_uart_slave/uart_tx_ready}

quietly catch {add wave -divider "AES"}
quietly catch {add wave -hex sim:/tb_soc_uart_runtime/dut/u_aes_slave/aes_plain_text}
quietly catch {add wave -hex sim:/tb_soc_uart_runtime/dut/u_aes_slave/aes_cipher_key}
quietly catch {add wave -hex sim:/tb_soc_uart_runtime/dut/u_aes_slave/aes_cipher_text}
quietly catch {add wave sim:/tb_soc_uart_runtime/dut/u_aes_slave/busy_q}
quietly catch {add wave sim:/tb_soc_uart_runtime/dut/u_aes_slave/done_q}


soc_sram_waves tb_soc_uart_runtime
catch {update}
soc_run tb_soc_uart_runtime
