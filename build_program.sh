#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# build_program.sh
#
# Build RV32I firmware:
#   program.S -> program.elf -> program.bin -> program.hex
#
# Run from project root:
#   ./build_program.sh
# ============================================================

SRC="${1:-program.S}"
ELF="program.elf"
BIN="program.bin"
HEX="program.hex"
DUMP="program.dump"

# Most Linux distributions package the bare-metal compiler under
# the riscv64-unknown-elf prefix. It can still emit RV32I binaries
# with -march=rv32i -mabi=ilp32.
if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    CROSS="riscv32-unknown-elf"
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    CROSS="riscv64-unknown-elf"
else
    echo "ERROR: RISC-V bare-metal toolchain not found."
    echo "Expected riscv32-unknown-elf-gcc or riscv64-unknown-elf-gcc."
    exit 1
fi

echo "Using toolchain: ${CROSS}"
echo "Source         : ${SRC}"

# Compile + link at instruction address 0x00000000.
#
# --no-relax keeps the linker from rewriting instruction sequences.
# -march=rv32i prevents compressed (RVC) instructions.
"${CROSS}-gcc" \
    -march=rv32i \
    -mabi=ilp32 \
    -nostdlib \
    -nostartfiles \
    -Wl,-Ttext=0x00000000 \
    -Wl,-e,start \
    -Wl,--no-relax \
    -o "${ELF}" \
    "${SRC}"

# Raw little-endian instruction bytes.
"${CROSS}-objcopy" -O binary "${ELF}" "${BIN}"

# Human-readable disassembly for debugging PC/instruction waveforms.
"${CROSS}-objdump" -D -M no-aliases,numeric "${ELF}" > "${DUMP}"

# Convert the little-endian binary stream to one 32-bit instruction
# word per line, exactly the format expected by:
#
#   logic [31:0] memory [0:1023];
#   $readmemh("program.hex", memory);
#
python3 - "${BIN}" "${HEX}" <<'PY'
from pathlib import Path
import sys

bin_path = Path(sys.argv[1])
hex_path = Path(sys.argv[2])

data = bin_path.read_bytes()

if len(data) % 4:
    data += b"\x00" * (4 - (len(data) % 4))

with hex_path.open("w") as f:
    for i in range(0, len(data), 4):
        word = int.from_bytes(data[i:i+4], byteorder="little")
        f.write(f"{word:08x}\n")

print(f"Wrote {len(data)//4} RV32I words to {hex_path}")
PY

echo ""
echo "Generated:"
echo "  ${ELF}"
echo "  ${BIN}"
echo "  ${HEX}"
echo "  ${DUMP}"

# If your instruction_memory.sv still loads the copy below rather
# than the root-level program.hex, uncomment this:
#
# cp "${HEX}" RV32I_Single_Cycle/program.hex
