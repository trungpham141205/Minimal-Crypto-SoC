module control_unit (
    input logic funct7,
    input logic [2:0]funct3,
    input logic [6:0]opcode,
    output logic reg_write,
    output logic [1:0]reg_back,
    output logic [2:0]imm_sel,
    output logic src_a_sel,
    output logic src_b_sel,
    output logic [3:0]alu_control,
    output logic mem_read,
    output logic mem_write,
    output logic [1:0]pc_sel
);
    
    always_comb begin
        case (opcode)
            //LUI
            7'b0110111: {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, alu_control, mem_read, mem_write, pc_sel} = 16'b1_11_000_0_0_0000_0_0_11;

            //AUIPC
            7'b0010111: {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, alu_control, mem_read, mem_write, pc_sel} = 16'b1_00_000_1_1_0000_0_0_11;

            //JAL
            7'b1101111: {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, alu_control, mem_read, mem_write, pc_sel} = 16'b1_10_001_0_0_0000_0_0_01;

            //B-TYPE
            7'b1100011: begin
                {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, mem_read, mem_write, pc_sel} = 12'b0_00_010_0_0_0_0_00;
                case (funct3)
                    //BEQ, BNE
                    3'b000,
                    3'b001: alu_control = 4'b0001;

                    //BLT, BGE
                    3'b100,
                    3'b101: alu_control = 4'b0011;

                    //BLTU, BGEU
                    3'b110,
                    3'b111: alu_control = 4'b0100;
                  
                    default: alu_control = 4'b0000;
                endcase
            end

            //JALR
            7'b1100111: {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, alu_control, mem_read, mem_write, pc_sel} = 16'b1_10_011_0_1_0000_0_0_10;
            
            //LOAD
            7'b0000011: {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, alu_control, mem_read, mem_write, pc_sel} = 16'b1_01_011_0_1_0000_1_0_11;

            //I-TYPE
            7'b0010011: begin
                {reg_write, reg_back, src_a_sel, src_b_sel, mem_read, mem_write, pc_sel} = 9'b1_00_0_1_0_0_11;
                casez ({funct3, funct7})
                        4'b000?: {imm_sel, alu_control} = 7'b011_0000;
                        4'b010?: {imm_sel, alu_control} = 7'b011_0011;
                        4'b011?: {imm_sel, alu_control} = 7'b011_0100;
                        4'b100?: {imm_sel, alu_control} = 7'b011_0101;
                        4'b110?: {imm_sel, alu_control} = 7'b011_1000;
                        4'b111?: {imm_sel, alu_control} = 7'b011_1001;

                    //SLLI
                    4'b0010: {imm_sel, alu_control} = 7'b101_0010;

                    //SRLI
                    4'b1010: {imm_sel, alu_control} = 7'b101_0110;

                    //SRAI
                    4'b1011: {imm_sel, alu_control} = 7'b101_0111;
                    default: {imm_sel, alu_control} = 7'b000_0000;
                endcase
            end

            //S-TYPE
            7'b0100011: {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, alu_control, mem_read, mem_write, pc_sel} = 16'b0_00_100_0_1_0000_0_1_11;

            //R-TYPE
            7'b0110011: begin
                {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, mem_read, mem_write, pc_sel} = 12'b1_00_000_0_0_0_0_11;
                case ({funct3, funct7})
                    4'b0000: alu_control = 4'b0000;
                    4'b0001: alu_control = 4'b0001;
                    4'b0010: alu_control = 4'b0010;
                    4'b0100: alu_control = 4'b0011;
                    4'b0110: alu_control = 4'b0100;
                    4'b1000: alu_control = 4'b0101;
                    4'b1010: alu_control = 4'b0110;
                    4'b1011: alu_control = 4'b0111;
                    4'b1100: alu_control = 4'b1000;
                    4'b1110: alu_control = 4'b1001;
                    default: alu_control = 4'b0000;
                endcase
            end

            default: {reg_write, reg_back, imm_sel, src_a_sel, src_b_sel, alu_control, mem_read, mem_write, pc_sel} = 16'b0_00_000_0_0_0000_0_0_11;
        endcase
    end

endmodule
