module aes_sub_word (
    input logic [31:0] word_in,
    output logic [31:0] word_out
);

    for (genvar i = 0; i < 4; i++) begin : gen_subword
        aes_sbox sbox_inst (
            .byte_in(word_in [8*i +: 8]),
            .byte_out(word_out [8*i +: 8])
        );
    end

endmodule
