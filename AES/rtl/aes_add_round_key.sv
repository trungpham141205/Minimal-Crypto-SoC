module aes_add_round_key (
    input logic [127:0] state_in,
    input logic [127:0] round_key,
    output logic [127:0] state_out
);

    always_comb begin
        state_out = state_in ^ round_key;
    end

endmodule
