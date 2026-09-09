module aes_key_expand_step (
    input logic [255:0] key_in,
    input logic [31:0] rcon,
    output logic [255:0] key_out,
    output logic [127:0] round_key_a,
    output logic [127:0] round_key_b
);

	logic [31:0] w [0:15]; 
    logic [31:0] rot_word_out;
    logic [31:0] sub_word_out;
    logic [31:0] sub_word_w11_out;

	for (genvar i = 0; i < 8; i++) begin
		assign w[i] = key_in[i*32 +: 32];
	end

	aes_rot_word rot_word_inst (
		.word_in(w[7]),
		.word_out(rot_word_out)
	); 

	aes_sub_word sub_word_inst (
		.word_in(rot_word_out),
		.word_out(sub_word_out)
	);

	always_comb begin
		w[8] = w[0] ^ sub_word_out ^ rcon;
		w[9] = w[1] ^ w[8];
		w[10] = w[2] ^ w[9];
		w[11] = w[3] ^ w[10];
	end

	aes_sub_word sub_word_w11_inst (
		.word_in(w[11]),
		.word_out(sub_word_w11_out)
	);

	always_comb begin
		w[12] = w[4] ^ sub_word_w11_out;
		w[13] = w[5] ^ w[12];
		w[14] = w[6] ^ w[13];
		w[15] = w[7] ^ w[14];
	end

	for (genvar i = 0; i < 8; i++) begin
		assign key_out[i*32 +: 32] = w[i+8];
	end

    always_comb begin
        round_key_a = {w[11], w[10], w[9], w[8]};
        round_key_b = {w[15], w[14], w[13], w[12]};
    end

endmodule
