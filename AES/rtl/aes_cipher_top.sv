module aes_cipher_top (
    input logic clk,
    input logic rst_n,
    input logic [127:0] plain_text,
    input logic [255:0] cipher_key,
    input logic valid_in,
    output logic [127:0] cipher_text,
    output logic valid_out
);

    logic [127:0] round_key [0:14];
    logic [127:0] plain_text_internal;
    logic [127:0] state_init;
    logic [127:0] state_out [1:14];
    logic [127:0] state_reg [0:14];
    logic valid_reg [0:14];

    for (genvar i = 0; i < 16; i++) begin : gen_reverse_plain_text_bytes
        assign plain_text_internal[8*i +: 8] = plain_text[8*(15-i) +: 8];
    end

    aes_key_schedule key_schedule_inst (
        .clk(clk),
        .rst_n(rst_n),
        .cipher_key(cipher_key),
        .round_key(round_key)
    );

    aes_add_round_key add_round_key_init (
        .state_in(plain_text_internal),
        .round_key(round_key[0]),
        .state_out(state_init)
    );

    for (genvar i = 1; i <= 13; i++) begin : gen_round
        aes_round round_inst (
            .state_in(state_reg[i-1]),
            .round_key(round_key[i]),
            .state_out(state_out[i])
        );
    end

    aes_round_last round_last_inst (
        .state_in(state_reg[13]),
        .round_key(round_key[14]),
        .state_out(state_out[14])
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i <= 14; i++) begin
                state_reg[i] <= '0;
                valid_reg[i] <= 1'b0;
            end
        end
        else begin
            state_reg[0] <= state_init;
            valid_reg[0] <= valid_in;

            for (int i = 1; i <= 14; i++) begin
                state_reg[i] <= state_out[i];
                valid_reg[i] <= valid_reg[i-1];
            end
        end
    end

    for (genvar i = 0; i < 16; i++) begin : gen_reverse_cipher_text_bytes
        assign cipher_text[8*i +: 8] = state_reg[14][8*(15-i) +: 8];
    end

    assign valid_out = valid_reg[14];

endmodule
