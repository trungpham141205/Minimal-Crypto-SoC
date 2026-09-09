# =============================================================================
# RV32I + AXI + SRAM + AES-256 + UART smoke-test firmware
#
# Address map
#   0x0000_0000 - 0x0000_01FF : SRAM
#   0x1000_0000 - 0x1000_0FFF : UART
#   0x2000_0000 - 0x2000_0FFF : AES
#
# PASS condition:
#   1) SRAM SW/LW round-trip succeeds.
#   2) AES-256 NIST vector matches:
#        KEY = 000102030405060708090A0B0C0D0E0F
#              101112131415161718191A1B1C1D1E1F
#        PT  = 00112233445566778899AABBCCDDEEFF
#        CT  = 8EA2B7CA516745BFEAFC49904B496089
#   3) CPU sends ASCII 'P' through UART.
#
# FAIL condition:
#   Any SRAM/AES comparison failure sends ASCII 'F' through UART.
#
# UART BAUDRATE is intentionally programmed to 0 for fast RTL simulation.
# With the current baud_gen this produces a TX tick every 8 clk cycles.
# =============================================================================

start:
    # -------------------------------------------------------------------------
    # 1. SRAM smoke test
    # -------------------------------------------------------------------------
    lui   x1, 0x12345
    addi  x1, x1, 0x678           # x1 = 0x12345678
    sw    x1, 0(x0)
    lw    x2, 0(x0)
    bne   x1, x2, fail

    # -------------------------------------------------------------------------
    # 2. AES-256 NIST known-answer test
    # -------------------------------------------------------------------------
    lui   x10, 0x20000            # x10 = AES_BASE = 0x2000_0000

    # Plaintext
    lui   x5, 0x00112
    addi  x5, x5, 0x233           # 0x00112233
    sw    x5, 0x10(x10)

    lui   x5, 0x44556
    addi  x5, x5, 0x677           # 0x44556677
    sw    x5, 0x14(x10)

    lui   x5, 0x8899B
    addi  x5, x5, -0x545          # 0x8899AABB
    sw    x5, 0x18(x10)

    lui   x5, 0xCCDDF
    addi  x5, x5, -0x101          # 0xCCDDEEFF
    sw    x5, 0x1C(x10)

    # AES-256 key
    lui   x5, 0x00010
    addi  x5, x5, 0x203           # 0x00010203
    sw    x5, 0x20(x10)

    lui   x5, 0x04050
    addi  x5, x5, 0x607           # 0x04050607
    sw    x5, 0x24(x10)

    lui   x5, 0x08091
    addi  x5, x5, -0x5F5          # 0x08090A0B
    sw    x5, 0x28(x10)

    lui   x5, 0x0C0D1
    addi  x5, x5, -0x1F1          # 0x0C0D0E0F
    sw    x5, 0x2C(x10)

    lui   x5, 0x10111
    addi  x5, x5, 0x213           # 0x10111213
    sw    x5, 0x30(x10)

    lui   x5, 0x14151
    addi  x5, x5, 0x617           # 0x14151617
    sw    x5, 0x34(x10)

    lui   x5, 0x18192
    addi  x5, x5, -0x5E5          # 0x18191A1B
    sw    x5, 0x38(x10)

    lui   x5, 0x1C1D2
    addi  x5, x5, -0x1E1          # 0x1C1D1E1F
    sw    x5, 0x3C(x10)

    # Start AES
    addi  x5, x0, 1
    sw    x5, 0x00(x10)

poll_aes:
    lw    x6, 0x04(x10)           # STATUS
    andi  x6, x6, 2               # DONE bit [1]
    beq   x6, x0, poll_aes

    # CT0 = 0x8EA2B7CA
    lw    x11, 0x40(x10)
    sw    x11, 0x20(x0)           # leave a copy in SRAM for debug
    lui   x12, 0x8EA2B
    addi  x12, x12, 0x7CA
    bne   x11, x12, fail

    # CT1 = 0x516745BF
    lw    x11, 0x44(x10)
    sw    x11, 0x24(x0)
    lui   x12, 0x51674
    addi  x12, x12, 0x5BF
    bne   x11, x12, fail

    # CT2 = 0xEAFC4990
    lw    x11, 0x48(x10)
    sw    x11, 0x28(x0)
    lui   x12, 0xEAFC5
    addi  x12, x12, -0x670
    bne   x11, x12, fail

    # CT3 = 0x4B496089
    lw    x11, 0x4C(x10)
    sw    x11, 0x2C(x0)
    lui   x12, 0x4B496
    addi  x12, x12, 0x089
    bne   x11, x12, fail

pass:
    # -------------------------------------------------------------------------
    # 3. UART PASS indication
    # -------------------------------------------------------------------------
    lui   x10, 0x10000            # UART_BASE
    sw    x0,  0x10(x10)          # BAUDRATE = 0, fast simulation
    addi  x5, x0, 1               # TX_EN=1, no parity, 1 stop
    sw    x5,  0x0C(x10)

wait_uart_pass:
    lw    x6, 0x08(x10)           # STATUS
    andi  x6, x6, 1               # TX_READY bit [0]
    beq   x6, x0, wait_uart_pass

    addi  x5, x0, 0x50            # ASCII 'P'
    sw    x5, 0x00(x10)           # TXDATA

pass_loop:
    jal   x0, pass_loop

fail:
    # -------------------------------------------------------------------------
    # Failure indication
    # -------------------------------------------------------------------------
    lui   x10, 0x10000
    sw    x0,  0x10(x10)
    addi  x5, x0, 1
    sw    x5,  0x0C(x10)

wait_uart_fail:
    lw    x6, 0x08(x10)
    andi  x6, x6, 1
    beq   x6, x0, wait_uart_fail

    addi  x5, x0, 0x46            # ASCII 'F'
    sw    x5, 0x00(x10)

fail_loop:
    jal   x0, fail_loop
