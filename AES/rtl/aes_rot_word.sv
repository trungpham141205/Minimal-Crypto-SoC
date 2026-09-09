module aes_rot_word (
    input logic [31:0] word_in,
    output logic [31:0] word_out
);
            
    always_comb begin
        word_out = {word_in[7:0], word_in[31:8]};
    end

endmodule
