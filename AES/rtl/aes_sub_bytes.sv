module aes_sub_bytes (
    input logic  [127:0] state_in,
    output logic [127:0] state_out
);

    for (genvar i = 0; i < 16; i++) begin : gen_sbox
        aes_sbox sbox_inst (
            .byte_in(state_in [8*i +: 8]),
            .byte_out(state_out [8*i +: 8])
        );
    end

endmodule
