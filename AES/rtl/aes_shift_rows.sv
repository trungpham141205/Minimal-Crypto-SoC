module aes_shift_rows (
    input logic [127:0] state_in,
    output logic [127:0] state_out
);

    always_comb begin
		// Column 0
        state_out[8*0 +: 8] = state_in[8*0  +: 8];
        state_out[8*1 +: 8] = state_in[8*5  +: 8];
        state_out[8*2 +: 8] = state_in[8*10 +: 8];
        state_out[8*3 +: 8] = state_in[8*15 +: 8];

        // Column 1
        state_out[8*4 +: 8] = state_in[8*4  +: 8];
        state_out[8*5 +: 8] = state_in[8*9  +: 8];
        state_out[8*6 +: 8] = state_in[8*14 +: 8];
        state_out[8*7 +: 8] = state_in[8*3  +: 8];

        // Column 2
        state_out[8*8  +: 8] = state_in[8*8  +: 8];
        state_out[8*9  +: 8] = state_in[8*13 +: 8];
        state_out[8*10 +: 8] = state_in[8*2  +: 8];
        state_out[8*11 +: 8] = state_in[8*7  +: 8];

        // Column 3
        state_out[8*12 +: 8] = state_in[8*12 +: 8];
        state_out[8*13 +: 8] = state_in[8*1  +: 8];
        state_out[8*14 +: 8] = state_in[8*6  +: 8];
        state_out[8*15 +: 8] = state_in[8*11 +: 8]; 
    end
    
endmodule
