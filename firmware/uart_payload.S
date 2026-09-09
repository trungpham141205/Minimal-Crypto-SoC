# =============================================================================
# UART-loaded AES-256 known-answer test.
#
# Link/run address : Instruction SRAM 0x0001_0000
# AES MMIO base    : 0x2000_0000
# Result mirror    : Shared SRAM 0x0000_0040 .. 0x0000_004c
#
# NIST AES-256 vector:
#   key        = 000102030405060708090a0b0c0d0e0f
#                101112131415161718191a1b1c1d1e1f
#   plaintext  = 00112233445566778899aabbccddeeff
#   ciphertext = 8ea2b7ca516745bfeafc49904b496089
#
# Completion convention used by tb_soc_uart_boot.sv:
#   x31 = 1: PASS
#   x31 = 2: FAIL
# =============================================================================

.section .text
.option norvc
.global start

start:
    addi  x31, x0, 0

    # x10 = AES MMIO base 0x2000_0000.
    lui   x10, 0x20000

    # Plaintext words PT0..PT3.
    lui   x5,  0x00112
    addi  x5,  x5, 0x233
    sw    x5,  0x10(x10)

    lui   x5,  0x44556
    addi  x5,  x5, 0x677
    sw    x5,  0x14(x10)

    lui   x5,  0x8899b
    addi  x5,  x5, -0x545
    sw    x5,  0x18(x10)

    lui   x5,  0xccddf
    addi  x5,  x5, -0x101
    sw    x5,  0x1c(x10)

    # AES-256 key words KEY0..KEY7.
    lui   x5,  0x00010
    addi  x5,  x5, 0x203
    sw    x5,  0x20(x10)

    lui   x5,  0x04050
    addi  x5,  x5, 0x607
    sw    x5,  0x24(x10)

    lui   x5,  0x08091
    addi  x5,  x5, -0x5f5
    sw    x5,  0x28(x10)

    lui   x5,  0x0c0d1
    addi  x5,  x5, -0x1f1
    sw    x5,  0x2c(x10)

    lui   x5,  0x10111
    addi  x5,  x5, 0x213
    sw    x5,  0x30(x10)

    lui   x5,  0x14151
    addi  x5,  x5, 0x617
    sw    x5,  0x34(x10)

    lui   x5,  0x18192
    addi  x5,  x5, -0x5e5
    sw    x5,  0x38(x10)

    lui   x5,  0x1c1d2
    addi  x5,  x5, -0x1e1
    sw    x5,  0x3c(x10)

    # CONTROL.START = 1.
    addi  x5,  x0, 1
    sw    x5,  0x00(x10)

poll_aes:
    lw    x6,  0x04(x10)
    andi  x6,  x6, 2
    beq   x6,  x0, poll_aes

    # Read, mirror and compare CT0.
    lw    x11, 0x40(x10)
    sw    x11, 0x40(x0)
    lui   x12, 0x8ea2b
    addi  x12, x12, 0x7ca
    bne   x11, x12, fail

    # CT1.
    lw    x11, 0x44(x10)
    sw    x11, 0x44(x0)
    lui   x12, 0x51674
    addi  x12, x12, 0x5bf
    bne   x11, x12, fail

    # CT2.
    lw    x11, 0x48(x10)
    sw    x11, 0x48(x0)
    lui   x12, 0xeafc5
    addi  x12, x12, -0x670
    bne   x11, x12, fail

    # CT3.
    lw    x11, 0x4c(x10)
    sw    x11, 0x4c(x0)
    lui   x12, 0x4b496
    addi  x12, x12, 0x089
    bne   x11, x12, fail

pass:
    addi  x31, x0, 1

pass_loop:
    jal   x0, pass_loop

fail:
    addi  x31, x0, 2

fail_loop:
    jal   x0, fail_loop
