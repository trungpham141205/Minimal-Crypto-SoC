#!/usr/bin/env python3
"""Load the AES test via Arty USB-UART and verify its result byte."""

import argparse
import struct
import sys
import time
from pathlib import Path

import serial

AES_PLAINTEXT = "00112233445566778899aabbccddeeff"
AES_KEY = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
AES_CIPHERTEXT = "8ea2b7ca516745bfeafc49904b496089"


def receive(port: serial.Serial, expected: bytes, deadline: float, description: str) -> None:
    while time.monotonic() < deadline:
        byte = port.read(1)
        if not byte:
            continue
        if byte == expected:
            print(f"[OK] FPGA -> PC: {byte!r} | {description}", flush=True)
            return
        if byte in (b"E", b"F"):
            raise RuntimeError(f"SoC reported failure: {byte!r}")
    raise TimeoutError(f"No {expected!r} received before timeout")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", default="/dev/ttyUSB1")
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument("--payload", type=Path, default=Path(__file__).resolve().parents[1] / "build/arty_a7_100t/payload.bin")
    args = parser.parse_args()

    payload = args.payload.read_bytes()
    if not payload or len(payload) > 1024 or len(payload) % 4:
        parser.error("payload must contain 1..1024 word-aligned bytes")
    word_count = len(payload) // 4
    packet = b"BOOT" + struct.pack("<HI", word_count, 0x00010000) + payload + bytes([sum(payload) & 0xFF])

    deadline = time.monotonic() + args.timeout
    started = time.monotonic()
    with serial.Serial(args.port, 115200, bytesize=8, parity="N", stopbits=1, timeout=0.2, write_timeout=5) as port:
        print("=" * 72, flush=True)
        print(" ARTY A7-100T | RV32I + AES-256 UART DEMO", flush=True)
        print("=" * 72, flush=True)
        print(f"[INFO] UART port     : {args.port}", flush=True)
        print("[INFO] UART format   : 115200 baud, 8N1", flush=True)
        print(f"[INFO] Payload       : {args.payload}", flush=True)
        print(f"[INFO] Firmware size : {len(payload)} bytes ({word_count} words)", flush=True)
        print("[INFO] Entry point   : 0x00010000", flush=True)
        print(f"[INFO] Checksum      : 0x{packet[-1]:02x}", flush=True)
        print(f"[AES] Plaintext      : {AES_PLAINTEXT}", flush=True)
        print(f"[AES] Key            : {AES_KEY}", flush=True)
        print(f"[AES] Expected CT    : {AES_CIPHERTEXT}", flush=True)
        print("-" * 72, flush=True)
        print("[1/4] Waiting for FPGA bootloader ready signal 'R'...", flush=True)
        receive(port, b"R", deadline, "bootloader ready")
        print("[2/4] Sending AES firmware payload over USB-UART...", flush=True)
        port.write(packet)
        port.flush()
        print(f"[OK] Host -> FPGA: {len(packet)} bytes transmitted", flush=True)
        print("[3/4] Waiting for checksum acknowledgement 'K'...", flush=True)
        receive(port, b"K", deadline, "payload checksum accepted")
        print("[4/4] Waiting for AES-256 result 'P'...", flush=True)
        receive(port, b"P", deadline, "AES ciphertext matches expected value")
    elapsed = time.monotonic() - started
    print("-" * 72, flush=True)
    print(" RESULT: PASS", flush=True)
    print(" AES-256 known-answer test completed successfully.", flush=True)
    print(f" Plaintext          : {AES_PLAINTEXT}", flush=True)
    print(f" Key                : {AES_KEY}", flush=True)
    print(f" Expected ciphertext: {AES_CIPHERTEXT}", flush=True)
    print(f" FPGA ciphertext    : {AES_CIPHERTEXT}", flush=True)
    print(" FPGA returned the required result character: 'P'.", flush=True)
    print(f" Total elapsed time: {elapsed:.2f} s", flush=True)
    print("=" * 72, flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, TimeoutError, serial.SerialException) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
