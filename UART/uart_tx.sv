module uart_tx (
    input  logic       clk,
    input  logic       rstn,
    input  logic       i_tx_en,
    input  logic [1:0] i_parity_mode,
    input  logic       i_frame_mode,
    input  logic       tx_baud_tick,
    input  logic [7:0] i_data,
    input  logic       i_data_valid,

    output logic       o_ready,
    output logic       o_tx
);

    // ============================================================
    // LOCAL PARAMETERS
    // ============================================================

    localparam logic [2:0] LAST_DATA_BIT = 3'd7;


    // ============================================================
    // FSM STATE DEFINITION
    // ============================================================

    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP
    } state_t;

    state_t current_state;
    state_t next_state;


    // ============================================================
    // DATAPATH REGISTERS
    // ============================================================

    logic [7:0] tx_hold_buffer;
    logic       tx_buffer_valid;

    logic [2:0] bit_cnt;
    logic       stop_cnt;

    logic       parity_bit;


    // ============================================================
    // CONTROL / HANDSHAKE SIGNALS
    // ============================================================

    logic tx_accept;
    logic parity_enable;

    logic frame_start;
    logic data_advance;
    logic stop_advance;


    // ============================================================
    // DIRECT CONNECTION
    // ============================================================

    assign parity_enable = i_parity_mode[0];


    // ============================================================
    // INPUT HANDSHAKE LOGIC
    // Owns: tx_accept
    // ============================================================

    always_comb begin
        tx_accept = i_data_valid && o_ready;
    end


    // ============================================================
    // FSM LAYER 1
    // STATE REGISTER
    // Owns: current_state
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            current_state <= TX_IDLE;
        end
        else if (!i_tx_en) begin
            current_state <= TX_IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end


    // ============================================================
    // FSM LAYER 2
    // NEXT-STATE LOGIC
    // Owns: next_state
    // ============================================================

    always_comb begin
        next_state = current_state;

        case (current_state)

            // ----------------------------------------------------
            // IDLE
            // Wait until data is available and baud tick arrives
            // ----------------------------------------------------
            TX_IDLE: begin
                if (tx_baud_tick &&
                    (tx_buffer_valid || tx_accept)) begin

                    next_state = TX_START;
                end
            end


            // ----------------------------------------------------
            // START
            // Send start bit for one baud period
            // ----------------------------------------------------
            TX_START: begin
                if (tx_baud_tick) begin
                    next_state = TX_DATA;
                end
            end


            // ----------------------------------------------------
            // DATA
            // Send 8 data bits
            // ----------------------------------------------------
            TX_DATA: begin
                if (tx_baud_tick &&
                    (bit_cnt == LAST_DATA_BIT)) begin

                    if (parity_enable) begin
                        next_state = TX_PARITY;
                    end
                    else begin
                        next_state = TX_STOP;
                    end
                end
            end


            // ----------------------------------------------------
            // PARITY
            // Send parity bit
            // ----------------------------------------------------
            TX_PARITY: begin
                if (tx_baud_tick) begin
                    next_state = TX_STOP;
                end
            end


            // ----------------------------------------------------
            // STOP
            // Send one or two stop bits
            // ----------------------------------------------------
            TX_STOP: begin
                if (tx_baud_tick) begin

                    if (!i_frame_mode || stop_cnt) begin
                        next_state = TX_IDLE;
                    end
                end
            end


            // ----------------------------------------------------
            // DEFAULT
            // ----------------------------------------------------
            default: begin
                next_state = TX_IDLE;
            end

        endcase
    end


    // ============================================================
    // FSM LAYER 3
    // OUTPUT / CONTROL LOGIC
    //
    // Owns:
    //   o_tx
    //   o_ready
    //   frame_start
    //   data_advance
    //   stop_advance
    // ============================================================

    always_comb begin

        // --------------------------------------------------------
        // Default values
        // --------------------------------------------------------

        o_tx         = 1'b1;
        o_ready      = 1'b0;

        frame_start  = 1'b0;
        data_advance = 1'b0;
        stop_advance = 1'b0;


        case (current_state)

            // ----------------------------------------------------
            // IDLE
            // UART line stays HIGH
            // ----------------------------------------------------
            TX_IDLE: begin

                o_tx = 1'b1;

                if (i_tx_en && !tx_buffer_valid) begin
                    o_ready = 1'b1;
                end

                if (tx_baud_tick &&
                    (tx_buffer_valid || tx_accept)) begin

                    frame_start = 1'b1;
                end
            end


            // ----------------------------------------------------
            // START BIT
            // UART start bit = LOW
            // ----------------------------------------------------
            TX_START: begin
                o_tx = 1'b0;
            end


            // ----------------------------------------------------
            // DATA
            // LSB transmitted first
            // ----------------------------------------------------
            TX_DATA: begin

                o_tx = tx_hold_buffer[bit_cnt];

                if (tx_baud_tick) begin
                    data_advance = 1'b1;
                end
            end


            // ----------------------------------------------------
            // PARITY
            // ----------------------------------------------------
            TX_PARITY: begin
                o_tx = parity_bit;
            end


            // ----------------------------------------------------
            // STOP
            // UART stop bit = HIGH
            // ----------------------------------------------------
            TX_STOP: begin

                o_tx = 1'b1;

                if (tx_baud_tick) begin
                    stop_advance = 1'b1;
                end
            end


            // ----------------------------------------------------
            // DEFAULT
            // ----------------------------------------------------
            default: begin
                o_tx    = 1'b1;
                o_ready = 1'b0;
            end

        endcase
    end


    // ============================================================
    // DATAPATH
    // TX HOLD BUFFER
    //
    // Owns: tx_hold_buffer
    //
    // Store accepted input byte.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            tx_hold_buffer <= '0;
        end
        else if (!i_tx_en) begin
            tx_hold_buffer <= '0;
        end
        else if (tx_accept) begin
            tx_hold_buffer <= i_data;
        end
    end


    // ============================================================
    // DATAPATH
    // TX BUFFER VALID
    //
    // Owns: tx_buffer_valid
    //
    // frame_start has higher priority because data may be
    // accepted and immediately consumed in the same clock cycle.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            tx_buffer_valid <= 1'b0;
        end
        else if (!i_tx_en) begin
            tx_buffer_valid <= 1'b0;
        end
        else if (frame_start) begin
            tx_buffer_valid <= 1'b0;
        end
        else if (tx_accept) begin
            tx_buffer_valid <= 1'b1;
        end
    end


    // ============================================================
    // DATAPATH
    // DATA BIT COUNTER
    //
    // Owns: bit_cnt
    //
    // Counts transmitted data bits from 0 to 7.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            bit_cnt <= '0;
        end
        else if (!i_tx_en) begin
            bit_cnt <= '0;
        end
        else if (frame_start) begin
            bit_cnt <= '0;
        end
        else if (data_advance) begin

            if (bit_cnt == LAST_DATA_BIT) begin
                bit_cnt <= '0;
            end
            else begin
                bit_cnt <= bit_cnt + 3'd1;
            end
        end
    end


    // ============================================================
    // DATAPATH
    // STOP BIT COUNTER
    //
    // Owns: stop_cnt
    //
    // frame_mode = 0 : one stop bit
    // frame_mode = 1 : two stop bits
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            stop_cnt <= 1'b0;
        end
        else if (!i_tx_en) begin
            stop_cnt <= 1'b0;
        end
        else if (current_state != TX_STOP) begin
            stop_cnt <= 1'b0;
        end
        else if (stop_advance) begin

            if (!i_frame_mode) begin
                stop_cnt <= 1'b0;
            end
            else begin
                stop_cnt <= ~stop_cnt;
            end
        end
    end


    // ============================================================
    // DATAPATH
    // PARITY GENERATION
    //
    // Owns: parity_bit
    //
    // Calculate parity when input data is accepted.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            parity_bit <= 1'b0;
        end
        else if (!i_tx_en) begin
            parity_bit <= 1'b0;
        end
        else if (tx_accept) begin

            case (i_parity_mode)

                2'b01: begin
                    parity_bit <= ~^i_data;
                end

                2'b11: begin
                    parity_bit <= ^i_data;
                end

                default: begin
                    parity_bit <= 1'b0;
                end

            endcase
        end
    end

endmodule
