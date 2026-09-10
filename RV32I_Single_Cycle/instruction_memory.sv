// =============================================================================
// Hard-wired Boot ROM
//
// Address range : 0x0000_0000 - 0x0000_0fff
// Contents      : UART bootloader (84 RV32I instruction words)
// Implementation: pure synthesizable combinational decode with no external
//                 hex-file dependency.
//
// The UART application payload is deliberately NOT stored here. At boot, the
// CPU executes this ROM, receives uart_payload.hex over UART, writes that image
// into Instruction SRAM at 0x0001_0000, and jumps to the downloaded entry.
// =============================================================================

module instruction_memory (
    input  logic [31:0] read_addr,
    output logic [31:0] instruction
);

    logic [9:0] word_addr;

    assign word_addr = read_addr[11:2];

    always_comb begin
        // RISC-V NOP for unused Boot ROM addresses.
        instruction = 32'h0000_0013;

        case (word_addr)
            10'd0:  instruction = 32'h1000_0437;
            10'd1:  instruction = 32'h0004_2823;
            10'd2:  instruction = 32'h0030_0293;
            10'd3:  instruction = 32'h0054_2623;
            10'd4:  instruction = 32'h0520_0513;
            10'd5:  instruction = 32'h1280_00ef;
            10'd6:  instruction = 32'h10c0_00ef;
            10'd7:  instruction = 32'h0420_0293;
            10'd8:  instruction = 32'h0e55_1c63;
            10'd9:  instruction = 32'h1000_00ef;
            10'd10: instruction = 32'h04f0_0293;
            10'd11: instruction = 32'h0e55_1663;
            10'd12: instruction = 32'h0f40_00ef;
            10'd13: instruction = 32'h04f0_0293;
            10'd14: instruction = 32'h0e55_1063;
            10'd15: instruction = 32'h0e80_00ef;
            10'd16: instruction = 32'h0540_0293;
            10'd17: instruction = 32'h0c55_1a63;
            10'd18: instruction = 32'h0dc0_00ef;
            10'd19: instruction = 32'h0005_0493;
            10'd20: instruction = 32'h0d40_00ef;
            10'd21: instruction = 32'h0085_1293;
            10'd22: instruction = 32'h0054_e4b3;
            10'd23: instruction = 32'h0a04_8e63;
            10'd24: instruction = 32'h1000_0293;
            10'd25: instruction = 32'h0a92_ea63;
            10'd26: instruction = 32'h0bc0_00ef;
            10'd27: instruction = 32'h0005_0913;
            10'd28: instruction = 32'h0b40_00ef;
            10'd29: instruction = 32'h0085_1293;
            10'd30: instruction = 32'h0059_6933;
            10'd31: instruction = 32'h0a80_00ef;
            10'd32: instruction = 32'h0105_1293;
            10'd33: instruction = 32'h0059_6933;
            10'd34: instruction = 32'h09c0_00ef;
            10'd35: instruction = 32'h0185_1293;
            10'd36: instruction = 32'h0059_6933;
            10'd37: instruction = 32'h0001_09b7;
            10'd38: instruction = 32'h0939_6063;
            10'd39: instruction = 32'h4009_8293;
            10'd40: instruction = 32'h0659_7c63;
            10'd41: instruction = 32'h0039_7293;
            10'd42: instruction = 32'h0602_9863;
            10'd43: instruction = 32'h0004_8a13;
            10'd44: instruction = 32'h0000_0a93;
            10'd45: instruction = 32'h0700_00ef;
            10'd46: instruction = 32'h0005_0313;
            10'd47: instruction = 32'h00aa_8ab3;
            10'd48: instruction = 32'h0640_00ef;
            10'd49: instruction = 32'h00aa_8ab3;
            10'd50: instruction = 32'h0085_1393;
            10'd51: instruction = 32'h0073_6333;
            10'd52: instruction = 32'h0540_00ef;
            10'd53: instruction = 32'h00aa_8ab3;
            10'd54: instruction = 32'h0105_1393;
            10'd55: instruction = 32'h0073_6333;
            10'd56: instruction = 32'h0440_00ef;
            10'd57: instruction = 32'h00aa_8ab3;
            10'd58: instruction = 32'h0185_1393;
            10'd59: instruction = 32'h0073_6333;
            10'd60: instruction = 32'h0069_a023;
            10'd61: instruction = 32'h0049_8993;
            10'd62: instruction = 32'hfffa_0a13;
            10'd63: instruction = 32'hfa0a_1ce3;
            10'd64: instruction = 32'h0ffa_fa93;
            10'd65: instruction = 32'h0200_00ef;
            10'd66: instruction = 32'h0155_1863;
            10'd67: instruction = 32'h04b0_0513;
            10'd68: instruction = 32'h02c0_00ef;
            10'd69: instruction = 32'h0009_0067;
            10'd70: instruction = 32'h0450_0513;
            10'd71: instruction = 32'h0200_00ef;
            10'd72: instruction = 32'h0000_006f;
            10'd73: instruction = 32'h0084_2283;
            10'd74: instruction = 32'h0022_f293;
            10'd75: instruction = 32'hfe02_8ce3;
            10'd76: instruction = 32'h0044_2503;
            10'd77: instruction = 32'h0ff5_7513;
            10'd78: instruction = 32'h0000_8067;
            10'd79: instruction = 32'h0084_2283;
            10'd80: instruction = 32'h0012_f293;
            10'd81: instruction = 32'hfe02_8ce3;
            10'd82: instruction = 32'h00a4_2023;
            10'd83: instruction = 32'h0000_8067;
            default: ;
        endcase
    end

endmodule
