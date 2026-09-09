module pc_adder (
    input logic [31:0]pc,
    output logic [31:0]pc_inc
);
    
    always_comb begin 
        pc_inc = pc + 4;
    end

endmodule