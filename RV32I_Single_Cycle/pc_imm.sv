module pc_imm (
    input logic [1:0]pc_sel,
    input logic [31:0]rs1_data,
    input logic [31:0]pc,
    input logic [31:0]imm,
    output logic [31:0]pc_target
);

    always_comb begin 
        case (pc_sel)
            2'b00,
            2'b01: begin
                pc_target = pc + imm;
            end
            2'b10: begin
                pc_target = (rs1_data + imm) & ~32'h1;
            end
            default: pc_target = pc + imm;
        endcase
    end

endmodule