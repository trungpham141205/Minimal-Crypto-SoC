module aes_key_schedule (
    input logic clk,
    input logic rst_n,
    input logic [255:0] cipher_key,
    output logic [127:0] round_key [0:14]
);

    localparam logic [31:0] RCON [0:6] = '{
        32'h00000001,
        32'h00000002,
        32'h00000004,
        32'h00000008,
        32'h00000010,
        32'h00000020,
        32'h00000040
    };

    logic [255:0] cipher_key_internal;
    logic [255:0] key_state_reg [0:13];
    logic [255:0] expanded_round_key [0:6];

    // Convert the external NIST byte order to the internal little-endian order.
    for (genvar i = 0; i < 32; i++) begin : gen_reverse_key_bytes
        assign cipher_key_internal[8*i +: 8] = cipher_key[8*(31-i) +: 8];
    end

    // Round 0 is consumed before the first pipeline register.
    assign round_key[0] = cipher_key_internal[127:0];

    // One expansion step runs in parallel with every odd AES round.
    for (genvar i = 0; i < 7; i++) begin : gen_key_expand
        aes_key_expand_step key_expand_inst (
            .key_in(key_state_reg[2*i]),
            .rcon(RCON[i]),
            .key_out(expanded_round_key[i]),
            .round_key_a(),
            .round_key_b()
        );
    end

    // At round i, key_state_reg[i-1] contains its matching pair of round keys.
    for (genvar i = 1; i <= 14; i++) begin : gen_round_key_select
        if ((i % 2) == 1) begin
            assign round_key[i] = key_state_reg[i-1][255:128];
        end
        else begin
            assign round_key[i] = key_state_reg[i-1][127:0];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i <= 13; i++) begin
                key_state_reg[i] <= '0;
            end
        end
        else begin
            key_state_reg[0] <= cipher_key_internal;

            for (int i = 1; i <= 13; i++) begin
                if ((i % 2) == 1) begin
                    key_state_reg[i] <= expanded_round_key[(i-1)/2];
                end
                else begin
                    key_state_reg[i] <= key_state_reg[i-1];
                end
            end
        end
    end

endmodule
