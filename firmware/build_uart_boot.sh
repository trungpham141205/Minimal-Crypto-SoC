#!/usr/bin/env bash
set -euo pipefail

# Build both images used by the UART boot integration test.
# Run from the KLTN project root:
#   bash firmware/build_uart_boot.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW_DIR="${PROJECT_ROOT}/firmware"

if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    CROSS="riscv32-unknown-elf"
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    CROSS="riscv64-unknown-elf"
else
    echo "ERROR: RISC-V bare-metal toolchain not found."
    exit 1
fi

build_image() {
    local source="$1"
    local link_address="$2"
    local stem="$3"
    local elf="${FW_DIR}/${stem}.elf"
    local bin="${FW_DIR}/${stem}.bin"
    local hex="${FW_DIR}/${stem}.hex"
    local dump="${FW_DIR}/${stem}.dump"

    "${CROSS}-gcc" \
        -march=rv32i \
        -mabi=ilp32 \
        -nostdlib \
        -nostartfiles \
        -Wl,-Ttext="${link_address}" \
        -Wl,-e,start \
        -Wl,--no-relax \
        -o "${elf}" \
        "${source}"

    "${CROSS}-objcopy" -O binary "${elf}" "${bin}"
    "${CROSS}-objdump" -D -M no-aliases,numeric "${elf}" > "${dump}"

    python3 - "${bin}" "${hex}" <<'PY'
from pathlib import Path
import sys

binary = Path(sys.argv[1]).read_bytes()
if len(binary) % 4:
    binary += b"\x00" * (4 - len(binary) % 4)

with Path(sys.argv[2]).open("w") as output:
    for offset in range(0, len(binary), 4):
        word = int.from_bytes(binary[offset:offset + 4], "little")
        output.write(f"{word:08x}\n")
PY

    echo "Built ${hex}"
}

build_image "${FW_DIR}/uart_bootloader.S" 0x00000000 program_uart_boot
build_image "${FW_DIR}/uart_payload.S"    0x00010000 uart_payload

payload_bytes=$(stat -c %s "${FW_DIR}/uart_payload.bin")
if (( payload_bytes == 0 || payload_bytes > 1024 || payload_bytes % 4 != 0 )); then
    echo "ERROR: UART payload must contain 1..1024 bytes and be word-aligned."
    exit 1
fi

echo "Payload size: ${payload_bytes} bytes / $((payload_bytes / 4)) words"
echo "UART boot images generated successfully."
