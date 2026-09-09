# ============================================================
# Secure SoC compile list
# Run from ~/PROJECT/KLTN
# ============================================================

# 1) Shared AXI interface MUST be compiled first
AXI/axi_full_if.sv

# 2) SRAM macro/model + 32-bit wrapper
RV32I_Single_Cycle/SRAM1RW256x32.v
RV32I_Single_Cycle/shared_sram_256x32_wrapper.sv
RV32I_Single_Cycle/instruction_sram_256x32_wrapper.sv
# 3) RV32I core
RV32I_Single_Cycle/alu.sv
RV32I_Single_Cycle/alu_src_a_mux.sv
RV32I_Single_Cycle/alu_src_b_mux.sv
RV32I_Single_Cycle/branch_unit.sv
RV32I_Single_Cycle/control_unit.sv
RV32I_Single_Cycle/immediate_generator.sv
RV32I_Single_Cycle/instruction_memory.sv
RV32I_Single_Cycle/instruction_fetch_router.sv
RV32I_Single_Cycle/l1_icache.sv
RV32I_Single_Cycle/pc_adder.sv
RV32I_Single_Cycle/pc_imm.sv
RV32I_Single_Cycle/program_counter.sv
RV32I_Single_Cycle/register_file.sv
RV32I_Single_Cycle/write_back_mux.sv
RV32I_Single_Cycle/risc_top.sv

# 4) UART core
UART/baud_gen.sv
UART/rx_sync.sv
UART/uart_tx.sv
UART/uart_rx.sv
UART/uart_core.sv

# 5) AES-256 core
AES/rtl/aes_sbox.sv
AES/rtl/aes_sub_bytes.sv
AES/rtl/aes_shift_rows.sv
AES/rtl/aes_mix_columns.sv
AES/rtl/aes_add_round_key.sv
AES/rtl/aes_rot_word.sv
AES/rtl/aes_sub_word.sv
AES/rtl/aes_key_expand_step.sv
AES/rtl/aes_key_schedule.sv
AES/rtl/aes_round.sv
AES/rtl/aes_round_last.sv
AES/rtl/aes_cipher_top.sv

# 6) AXI integration layer
AXI/cpu_axi_request_arbiter.sv
AXI/axi_master_wrapper.sv
AXI/axi_instruction_sram_slave.sv
AXI/axi_shared_sram_slave.sv
AXI/axi_sram_controller.sv
AXI/uart_axi_slave.sv
AXI/aes_axi_slave.sv
AXI/axi_interconnect_1m4s.sv

# 7) SoC top (each Do/*.do script compiles its own testbench)
soc_top.sv
