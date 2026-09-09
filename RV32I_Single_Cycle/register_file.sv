module register_file (
    input logic reg_write,
    input logic stall_i,
    input logic clk,
    input logic [4:0]rs1,
    input logic [4:0]rs2,
    input logic [4:0]rd,
    input logic [31:0]write_data,
    output logic [31:0]rs1_data,
    output logic [31:0]rs2_data
);

    logic [31:0]registers [0:31];

    always_ff @(posedge clk) begin
        if((reg_write & !stall_i) && rd != 5'b0) begin
            registers[rd] <= write_data;
        end
    end

    always_comb begin
        rs1_data = (rs1 != 0) ? registers[rs1] : 32'b0;
        rs2_data = (rs2 != 0) ? registers[rs2] : 32'b0;
    end

endmodule
