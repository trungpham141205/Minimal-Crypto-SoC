# CPU boots from the existing instruction ROM, writes three words to the
# AXI-visible instruction SRAM, reads them back, and copies them to shared SRAM.
#
# Address map used by soc_top:
#   instruction SRAM : 0x0001_0000 - 0x0001_03ff
#   shared SRAM      : 0x0000_0000 - 0x0000_01ff (decoded window)
#
# Completion visible to the testbench:
#   x31 = 1 : PASS
#   x31 = 2 : FAIL

.section .text
.global start

start:
    addi  x31, x0, 0
    lui   x10, 0x00010          # x10 = instruction SRAM base

    lui   x1, 0x11223
    addi  x1, x1, 0x344        # 0x11223344

    lui   x2, 0x89abd
    addi  x2, x2, -0x211       # 0x89abcdef

    lui   x3, 0xdeadc
    addi  x3, x3, -0x111       # 0xdeadbeef

    # Write beginning, adjacent word, and final word of instruction SRAM.
    sw    x1, 0x000(x10)
    sw    x2, 0x004(x10)
    sw    x3, 0x3fc(x10)

    # Read from instruction SRAM, then check before copying.
    lw    x11, 0x000(x10)
    lw    x12, 0x004(x10)
    lw    x13, 0x3fc(x10)
    bne   x11, x1, fail
    bne   x12, x2, fail
    bne   x13, x3, fail

    # x0 is the shared SRAM base. Copy to its decoded first and final words.
    sw    x11, 0x000(x0)
    sw    x12, 0x004(x0)
    sw    x13, 0x1fc(x0)

    # Read shared SRAM back and compare with the original patterns.
    lw    x14, 0x000(x0)
    lw    x15, 0x004(x0)
    lw    x16, 0x1fc(x0)
    bne   x14, x1, fail
    bne   x15, x2, fail
    bne   x16, x3, fail

    addi  x31, x0, 1
pass_loop:
    jal   x0, pass_loop

fail:
    addi  x31, x0, 2
fail_loop:
    jal   x0, fail_loop
