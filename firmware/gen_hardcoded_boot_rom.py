#!/usr/bin/env python3
"""Generate synthesizable instruction_memory.sv from a Boot ROM word hex file."""

from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


if len(sys.argv) != 3:
    fail("usage: gen_hardcoded_boot_rom.py INPUT.hex OUTPUT.sv")

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
words = []

for line_number, raw_line in enumerate(input_path.read_text().splitlines(), 1):
    text = raw_line.split("#", 1)[0].split("//", 1)[0].strip()
    if not text:
        continue
    if not re.fullmatch(r"[0-9a-fA-F]{8}", text):
        fail(f"{input_path}:{line_number}: expected exactly one 32-bit hex word")
    words.append(int(text, 16))

if not words:
    fail("Boot ROM image is empty")
if len(words) > 1024:
    fail(f"Boot ROM image has {len(words)} words; maximum is 1024")

lines = [
    "// Generated hard-wired Boot ROM. Do not edit instruction words manually.",
    "// Source image: firmware/program_uart_boot.hex",
    "module instruction_memory (",
    "    input  logic [31:0] read_addr,",
    "    output logic [31:0] instruction",
    ");",
    "",
    "    logic [9:0] word_addr;",
    "    assign word_addr = read_addr[11:2];",
    "",
    "    always_comb begin",
    "        instruction = 32'h0000_0013; // RISC-V NOP",
    "        case (word_addr)",
]

for index, word in enumerate(words):
    hex_word = f"{word:08x}"
    grouped = f"{hex_word[0:4]}_{hex_word[4:8]}"
    lines.append(f"            10'd{index}: instruction = 32'h{grouped};")

lines.extend([
    "            default: ;",
    "        endcase",
    "    end",
    "",
    "endmodule",
    "",
])

output_path.write_text("\n".join(lines))
print(f"Generated {output_path} with {len(words)} hard-wired words")
