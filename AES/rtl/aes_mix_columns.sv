module aes_mix_columns (
    input logic [127:0] state_in,
    output logic [127:0] state_out
);

    function automatic logic [7:0] xtime (
        input logic [7:0] value
    );
        begin
            xtime = (value[7] == 1'b1) ? ({value[6:0], 1'b0} ^ 8'h1b) : {value[6:0], 1'b0};
        end
    endfunction

    function automatic logic [31:0] mix_one_column (
        input logic [31:0] column_in
    );
        logic [7:0] s0;
        logic [7:0] s1;
        logic [7:0] s2;
        logic [7:0] s3;

        logic [7:0] mul2_s0;
        logic [7:0] mul2_s1;
        logic [7:0] mul2_s2;
        logic [7:0] mul2_s3;

        logic [7:0] r0;
        logic [7:0] r1;
        logic [7:0] r2;
        logic [7:0] r3;

        begin
            s0 = column_in[7:0];
            s1 = column_in[15:8];
            s2 = column_in[23:16];
            s3 = column_in[31:24];

            mul2_s0 = xtime(s0);
            mul2_s1 = xtime(s1);
            mul2_s2 = xtime(s2);
            mul2_s3 = xtime(s3);

            r0 = mul2_s0 ^ (mul2_s1 ^ s1) ^ s2 ^ s3;
            r1 = s0 ^ mul2_s1 ^ (mul2_s2 ^ s2) ^ s3;
            r2 = s0 ^ s1 ^ mul2_s2 ^ (mul2_s3 ^ s3);
            r3 = (mul2_s0 ^ s0) ^ s1 ^ s2 ^ mul2_s3;

            mix_one_column = {r3, r2, r1, r0};
        end
    endfunction

    always_comb begin
        for (int col = 0; col < 4; col++) begin
            state_out[32*col +: 32] = mix_one_column(state_in[32*col +: 32]);
        end
    end

endmodule
