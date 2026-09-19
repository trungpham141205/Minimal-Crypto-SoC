# Minimal-Crypto-SoC
## Arty A7-100T UART/AES bring-up

The board uses its 100 MHz oscillator at E3. `arty_a7_top.sv` generates a
47.619 MHz SoC clock with an MMCM and connects USB-UART to A9 (PC to FPGA)
and D10 (FPGA to PC). `btn[0]` resets the SoC. LED0 shows clock lock,
LED1 CPU stall and LED2 AES done. The UART runs at 115200 8N1.

From the project root:

```bash
bash firmware/build_arty_a7.sh
vivado -mode batch -source build_arty_a7.tcl
```

The routed timing report is `build/arty_a7_100t/timing_summary.rpt` and
the bitstream is `build/arty_a7_100t/arty_a7_100t.bit`. Start the host
receiver *before* programming the FPGA, because the boot ROM emits its
ready byte once after reset:

```bash
python3 firmware/arty_uart_boot.py --port /dev/ttyUSB1
# In another terminal:
vivado -mode batch -source program_arty_a7.tcl
```

The host sends the AES firmware over UART. The board answers `R` when ready,
`K` after validating the payload checksum, and finally `P` if all four
AES-256 ciphertext words match the known answer. `E` denotes a boot error;
`F` denotes an AES mismatch. Press button 0 to reset and repeat. The
payload and hard-wired boot ROM for this board are generated separately
under `build/arty_a7_100t/`. The existing simulation boot ROM retains its
fast UART divider.
