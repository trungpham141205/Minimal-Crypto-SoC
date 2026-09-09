module alu_src_b_mux(
    input logic src_b_sel,
    input logic [31:0]reg_data,
    input logic [31:0]imm_data,
    output logic [31:0]src_b
);

    assign src_b = src_b_sel ? imm_data : reg_data;

endmodule