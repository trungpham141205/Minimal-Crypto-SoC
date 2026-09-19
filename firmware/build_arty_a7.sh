#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${project_root}/build/arty_a7_100t"
mkdir -p "${build_dir}"

if command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    cross=riscv32-unknown-elf
elif command -v riscv64-unknown-elf-gcc >/dev/null 2>&1; then
    cross=riscv64-unknown-elf
else
    echo 'RISC-V bare-metal compiler is required.' >&2
    exit 1
fi

build_image() {
    local stem="$1" address="$2" source="$3" define="$4"
    "${cross}-gcc" -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles \
        -Wl,-Ttext="${address}" -Wl,-e,start -Wl,--no-relax \
        ${define} -o "${build_dir}/${stem}.elf" "${source}"
    "${cross}-objcopy" -O binary "${build_dir}/${stem}.elf" "${build_dir}/${stem}.bin"
    "${cross}-objdump" -D -M no-aliases,numeric "${build_dir}/${stem}.elf" > "${build_dir}/${stem}.dump"
    python3 - "${build_dir}/${stem}.bin" "${build_dir}/${stem}.hex" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
if not data or len(data) % 4:
    raise SystemExit("Firmware image must be nonempty and word aligned")
Path(sys.argv[2]).write_text("".join(
    f"{int.from_bytes(data[i:i+4], 'little'):08x}\n"
    for i in range(0, len(data), 4)
))
PY
}

build_image boot 0x00000000 "${project_root}/firmware/uart_bootloader.S" -DBOARD_UART_DIVIDER=51
build_image payload 0x00010000 "${project_root}/firmware/uart_payload.S" ''
python3 "${project_root}/firmware/gen_hardcoded_boot_rom.py" \
    "${build_dir}/boot.hex" "${build_dir}/instruction_memory.sv"

payload_size=$(stat -c %s "${build_dir}/payload.bin")
if (( payload_size > 1024 )); then
    echo "Payload is ${payload_size} bytes; Instruction SRAM holds 1024." >&2
    exit 1
fi
echo "Arty firmware: ${payload_size} payload bytes; boot ROM and UART at 115200 baud."
