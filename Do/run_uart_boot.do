# Run from the KLTN project root:
#   vsim -do Do/run_uart_boot.do
# Batch:
#   vsim -c -l uart_boot_run.log -do "do Do/run_uart_boot.do; quit -force"

do Do/soc_common.do
onerror {quit -force -code 1}
onbreak {resume}

set uart_boot_root [pwd]
set uart_boot_run_dir [file join $uart_boot_root sim tb_soc_uart_boot]
file mkdir $uart_boot_run_dir
file copy -force firmware/uart_payload.hex \
    [file join $uart_boot_run_dir uart_payload.hex]

# soc_prepare copies this image to program.hex for instruction_memory.sv.
soc_prepare tb_soc_uart_boot firmware/program_uart_boot.hex

catch {add wave -divider "UART BOOT PINS"}
catch {add wave sim:/tb_soc_uart_boot/uart_rx_i}
catch {add wave sim:/tb_soc_uart_boot/uart_tx_o}

catch {add wave -divider "CPU EXECUTION"}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_cpu/pc_debug}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_cpu/instr_debug}
catch {add wave sim:/tb_soc_uart_boot/dut/cpu_stall_debug}

catch {add wave -divider "UART RX MMIO"}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_uart_slave/uart_rx_data}
catch {add wave sim:/tb_soc_uart_boot/dut/u_uart_slave/uart_rx_valid}
catch {add wave sim:/tb_soc_uart_boot/dut/u_uart_slave/uart_rx_ready}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_uart_slave/tx_data_q}
catch {add wave sim:/tb_soc_uart_boot/dut/u_uart_slave/tx_pending_q}

catch {add wave -divider "INSTRUCTION SRAM LOAD"}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/instr_sram_axi/awaddr}
catch {add wave sim:/tb_soc_uart_boot/dut/instr_sram_axi/awvalid}
catch {add wave sim:/tb_soc_uart_boot/dut/instr_sram_axi/awready}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/instr_sram_axi/wdata}
catch {add wave sim:/tb_soc_uart_boot/dut/instr_sram_axi/wvalid}
catch {add wave sim:/tb_soc_uart_boot/dut/instr_sram_axi/wready}
catch {add wave sim:/tb_soc_uart_boot/dut/instr_sram_axi/bvalid}
catch {add wave sim:/tb_soc_uart_boot/dut/instr_sram_axi/bready}

catch {add wave -divider "L1 I-CACHE"}
catch {add wave sim:/tb_soc_uart_boot/dut/icache_invalidate}
catch {add wave sim:/tb_soc_uart_boot/dut/icache_hit}
catch {add wave sim:/tb_soc_uart_boot/dut/icache_miss}
catch {add wave sim:/tb_soc_uart_boot/dut/icache_busy}
catch {add wave sim:/tb_soc_uart_boot/dut/u_l1_icache/state_q}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_l1_icache/miss_line_base_q}
catch {add wave -unsigned sim:/tb_soc_uart_boot/dut/u_l1_icache/refill_word_q}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/axi_fetch_addr}
catch {add wave sim:/tb_soc_uart_boot/dut/axi_fetch_req}
catch {add wave sim:/tb_soc_uart_boot/dut/axi_fetch_valid}

catch {add wave -divider "AES-256 KAT"}
catch {add wave sim:/tb_soc_uart_boot/dut/u_aes_slave/busy_q}
catch {add wave sim:/tb_soc_uart_boot/dut/u_aes_slave/done_q}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_aes_slave/pt_q}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_aes_slave/key_q}
catch {add wave -hex sim:/tb_soc_uart_boot/dut/u_aes_slave/ct_q}
catch {add wave -hex sim:/tb_soc_uart_boot/shared_ct_write_seen}

soc_sram_waves tb_soc_uart_boot
catch {update}
soc_run tb_soc_uart_boot
