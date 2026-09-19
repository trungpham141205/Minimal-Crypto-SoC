# =============================================================================
# Minimal UART Boot ROM firmware for the current RV32I Secure SoC
#
# UART protocol, all multi-byte fields are little-endian:
#   Host waits for     : 'R' (0x52)
#   Host sends         : 'B' 'O' 'O' 'T'
#   Host sends         : word_count[15:0]
#   Host sends         : entry_point[31:0]
#   Host sends         : word_count * 4 payload bytes
#   Host sends         : checksum8 = sum(payload bytes) modulo 256
#   Boot ROM replies   : 'K' (0x4b) and jumps, or 'E' (0x45) on error
#
# Fixed memory map:
#   UART               : 0x1000_0000
#   Instruction SRAM   : 0x0001_0000 - 0x0001_03ff
#
# Register allocation:
#   x8  : UART base
#   x9  : payload word count
#   x18 : entry point
#   x19 : current Instruction SRAM write pointer
#   x20 : remaining word count
#   x21 : additive checksum accumulator
#   x10 : uart_getc return / uart_putc argument
#   x1  : subroutine return address
# =============================================================================

.section .text
.option norvc
.global start

start:
    # UART_BASE = 0x1000_0000
    lui   x8, 0x10000

#ifdef BOARD_UART_DIVIDER
    # (1000/21) MHz / (8 * (51 + 1)) = 114468.9 baud (0.63% below 115200).
    addi  x5, x0, BOARD_UART_DIVIDER
    sw    x5, 16(x8)
#else
    # Fast simulation setting, used by the existing RTL testbench.
    sw    x0, 16(x8)
#endif

    # CONTROL[1:0] = RX_EN | TX_EN
    addi  x5, x0, 3
    sw    x5, 12(x8)

    # Tell the host that Boot ROM is ready.
    addi  x10, x0, 0x52          # 'R'
    jal   x1, uart_putc

    # -------------------------------------------------------------------------
    # Receive and validate magic "BOOT".
    # -------------------------------------------------------------------------
    jal   x1, uart_getc
    addi  x5, x0, 0x42           # 'B'
    bne   x10, x5, boot_error

    jal   x1, uart_getc
    addi  x5, x0, 0x4f           # 'O'
    bne   x10, x5, boot_error

    jal   x1, uart_getc
    addi  x5, x0, 0x4f           # 'O'
    bne   x10, x5, boot_error

    jal   x1, uart_getc
    addi  x5, x0, 0x54           # 'T'
    bne   x10, x5, boot_error

    # -------------------------------------------------------------------------
    # Receive word_count as uint16 little-endian. Valid range is 1..256.
    # -------------------------------------------------------------------------
    jal   x1, uart_getc
    addi  x9, x10, 0

    jal   x1, uart_getc
    slli  x5, x10, 8
    or    x9, x9, x5

    beq   x9, x0, boot_error
    addi  x5, x0, 256
    bltu  x5, x9, boot_error      # Error when 256 < word_count.

    # -------------------------------------------------------------------------
    # Receive 32-bit entry point, little-endian.
    # -------------------------------------------------------------------------
    jal   x1, uart_getc
    addi  x18, x10, 0

    jal   x1, uart_getc
    slli  x5, x10, 8
    or    x18, x18, x5

    jal   x1, uart_getc
    slli  x5, x10, 16
    or    x18, x18, x5

    jal   x1, uart_getc
    slli  x5, x10, 24
    or    x18, x18, x5

    # Entry must be aligned and inside the 1-KiB Instruction SRAM window.
    lui   x19, 0x00010            # 0x0001_0000
    bltu  x18, x19, boot_error
    addi  x5, x19, 1024           # First address outside Instruction SRAM.
    bgeu  x18, x5, boot_error
    andi  x5, x18, 3
    bne   x5, x0, boot_error

    addi  x20, x9, 0              # remaining_words = word_count
    addi  x21, x0, 0              # checksum = 0

payload_loop:
    # Byte 0
    jal   x1, uart_getc
    addi  x6, x10, 0
    add   x21, x21, x10

    # Byte 1
    jal   x1, uart_getc
    add   x21, x21, x10
    slli  x7, x10, 8
    or    x6, x6, x7

    # Byte 2
    jal   x1, uart_getc
    add   x21, x21, x10
    slli  x7, x10, 16
    or    x6, x6, x7

    # Byte 3
    jal   x1, uart_getc
    add   x21, x21, x10
    slli  x7, x10, 24
    or    x6, x6, x7

    # Full-word store to executable SRAM through the normal CPU AXI path.
    sw    x6, 0(x19)
    addi  x19, x19, 4
    addi  x20, x20, -1
    bne   x20, x0, payload_loop

    # -------------------------------------------------------------------------
    # Validate checksum, acknowledge, and transfer control to the payload.
    # -------------------------------------------------------------------------
    andi  x21, x21, 255
    jal   x1, uart_getc
    bne   x10, x21, boot_error

    addi  x10, x0, 0x4b          # 'K'
    jal   x1, uart_putc

    jalr  x0, 0(x18)

boot_error:
    addi  x10, x0, 0x45          # 'E'
    jal   x1, uart_putc

boot_error_loop:
    jal   x0, boot_error_loop

# -----------------------------------------------------------------------------
# uart_getc
#   Blocks until STATUS.RX_VALID is one, then reads RXDATA.
#   Returns zero-extended byte in x10. Clobbers x5.
# -----------------------------------------------------------------------------
uart_getc:
uart_getc_poll:
    lw    x5, 8(x8)
    andi  x5, x5, 2
    beq   x5, x0, uart_getc_poll
    lw    x10, 4(x8)
    andi  x10, x10, 255
    jalr  x0, 0(x1)

# -----------------------------------------------------------------------------
# uart_putc
#   Blocks until STATUS.TX_READY is one, then writes x10[7:0] to TXDATA.
#   Clobbers x5.
# -----------------------------------------------------------------------------
uart_putc:
uart_putc_poll:
    lw    x5, 8(x8)
    andi  x5, x5, 1
    beq   x5, x0, uart_putc_poll
    sw    x10, 0(x8)
    jalr  x0, 0(x1)
