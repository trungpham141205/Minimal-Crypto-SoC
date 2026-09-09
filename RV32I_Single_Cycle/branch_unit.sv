module branch_unit(
    input logic [1:0]pc_sel,
    input logic zero,
    input logic [2:0]funct3,
    input logic [31:0]pc_inc,
    input logic [31:0]pc_target,
    output logic [31:0]pc_next
);

    always_comb begin
        case (pc_sel)
            2'b00: begin
                case (funct3)
                    3'b000,
                    3'b101,
                    3'b111: pc_next = zero ? pc_target : pc_inc;
                    3'b001,
                    3'b100,
                    3'b110: pc_next = zero ? pc_inc : pc_target;
                    default: pc_next = pc_inc;
                endcase
            end
            2'b01,
            2'b10: begin
                pc_next = pc_target;
            end
            2'b11: pc_next = pc_inc;
            default: pc_next = pc_inc;
        endcase
    end

endmodule