module write_back_mux (
    input logic [1:0]reg_back,
    input logic [31:0]alu_result,
    input logic [31:0]data_memory,
    input logic [31:0]pc_adder,
    input logic [31:0]imm,
    output logic [31:0]write_back
);

    always_comb begin
        case (reg_back)
            2'b00: write_back = alu_result;
            2'b01: write_back = data_memory;
            2'b10: write_back = pc_adder;
            2'b11: write_back = imm;
            default: write_back = 32'h00000000;
        endcase
    end
    
endmodule