module alu_src_a_mux(
    input logic src_a_sel,
    input logic [31:0]reg_data,
    input logic [31:0]pc_data,
    output logic [31:0] src_a
);

    assign src_a = src_a_sel ? pc_data : reg_data;

endmodule