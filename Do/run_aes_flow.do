# Run from /home/trungpham/PROJECT/KLTN:
#   vsim -do Do/run_aes_flow.do
# Batch:
#   vsim -c -do "do Do/run_aes_flow.do; quit -force"
# Firmware: firmware/program_aes_flow.hex
# Outputs: sim/tb_soc_aes_flow/

do Do/soc_common.do
onerror {quit -force -code 1}
onbreak {resume}
soc_prepare tb_soc_aes_flow firmware/program_aes_flow.hex

quietly catch {add wave -divider "CPU"}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/u_cpu/pc_debug}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/u_cpu/instr_debug}
quietly catch {add wave sim:/tb_soc_aes_flow/cpu_stall_debug}

quietly catch {add wave -divider "AXI"}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/cpu_axi/awaddr}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/cpu_axi/awvalid}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/cpu_axi/awready}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/cpu_axi/wdata}
quietly catch {add wave -binary sim:/tb_soc_aes_flow/dut/cpu_axi/wstrb}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/cpu_axi/araddr}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/cpu_axi/arvalid}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/cpu_axi/arready}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/cpu_axi/rdata}

quietly catch {add wave -divider "AES"}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/u_aes_slave/aes_plain_text}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/u_aes_slave/aes_cipher_key}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/u_aes_slave/aes_cipher_text}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/u_aes_slave/busy_q}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/u_aes_slave/done_q}

quietly catch {add wave -divider "UART AES RESULT"}
quietly catch {add wave sim:/tb_soc_aes_flow/uart_tx_o}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/dut/u_uart_slave/tx_data_q}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/u_uart_slave/tx_pending_q}
quietly catch {add wave sim:/tb_soc_aes_flow/dut/u_uart_slave/uart_tx_ready}
quietly catch {add wave -hex sim:/tb_soc_aes_flow/uart_ciphertext}
quietly catch {add wave -unsigned sim:/tb_soc_aes_flow/uart_count}

soc_sram_waves tb_soc_aes_flow
catch {update}
soc_run tb_soc_aes_flow
