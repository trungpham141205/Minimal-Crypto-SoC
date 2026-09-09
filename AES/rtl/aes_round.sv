module aes_round (
    input logic [127:0] state_in,
    input logic [127:0] round_key,
    output logic [127:0] state_out
);

    logic [127:0] state_out_sub_bytes;
    logic [127:0] state_out_shift_rows;
    logic [127:0] state_out_mix_columns;

    aes_sub_bytes sub_bytes_inst (
        .state_in(state_in),
        .state_out(state_out_sub_bytes)
    );   

    aes_shift_rows shift_rows_inst (
        .state_in(state_out_sub_bytes),
        .state_out(state_out_shift_rows)
    );

    aes_mix_columns mix_columns_inst (
        .state_in(state_out_shift_rows),
        .state_out(state_out_mix_columns)
    );

   aes_add_round_key add_round_key_inst (
        .state_in(state_out_mix_columns),
        .round_key(round_key),
        .state_out(state_out)
    );

endmodule
