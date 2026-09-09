module uart_rx (
    input  logic       clk,
    input  logic       rstn,
    input  logic       i_rx_en,
    input  logic [1:0] i_parity_mode,
    input  logic       i_frame_mode,
    input  logic       rx_baud_tick,
    input  logic       rx_sync_data,

    output logic [7:0] o_data,
    output logic       o_data_valid,
    input  logic       i_ready,

    output logic       o_parity_err,
    output logic       o_frame_err
);

    // ============================================================
    // LOCAL PARAMETERS
    // ============================================================

    localparam logic [2:0] START_MID_COUNT      = 3'd3;
    localparam logic [2:0] SAMPLE_PERIOD_COUNT = 3'd7;
    localparam logic [2:0] LAST_DATA_BIT       = 3'd7;


    // ============================================================
    // FSM STATE DEFINITION
    // ============================================================

    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP
    } state_t;

    state_t current_state;
    state_t next_state;


    // ============================================================
    // DATAPATH REGISTERS
    // ============================================================

    logic [7:0] rx_shift_buffer;
    logic [7:0] rx_hold_buffer;

    logic       rx_hold_valid;

    logic [2:0] sample_cnt;
    logic [2:0] bit_cnt;

    logic       stop_cnt;

    logic       parity_error_pending;
    logic       parity_error_reg;

    logic       frame_error_pending;
    logic       frame_error_reg;

    logic       parity_enable;


    // ============================================================
    // FSM CONTROL SIGNALS
    // ============================================================

    logic sample_tick_en;
    logic sample_terminal;

    logic data_sample_en;
    logic parity_sample_en;
    logic stop_sample_en;

    logic frame_complete;


    // ============================================================
    // DIRECT CONNECTION
    // ============================================================

    assign parity_enable = i_parity_mode[0];

    assign o_data       = rx_hold_buffer;
    assign o_data_valid = rx_hold_valid;

    assign o_parity_err = parity_error_reg;
    assign o_frame_err  = frame_error_reg;


    // ============================================================
    // FSM LAYER 1
    // STATE REGISTER
    // Owns: current_state
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            current_state <= RX_IDLE;
        end
        else if (!i_rx_en) begin
            current_state <= RX_IDLE;
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
            // Detect falling/start-bit condition
            // ----------------------------------------------------
            RX_IDLE: begin
                if (rx_baud_tick && !rx_sync_data) begin
                    next_state = RX_START;
                end
            end


            // ----------------------------------------------------
            // START
            // Validate start bit at its middle point
            // ----------------------------------------------------
            RX_START: begin
                if (rx_baud_tick &&
                    (sample_cnt == START_MID_COUNT)) begin

                    if (!rx_sync_data) begin
                        next_state = RX_DATA;
                    end
                    else begin
                        next_state = RX_IDLE;
                    end
                end
            end


            // ----------------------------------------------------
            // DATA
            // Receive 8 data bits
            // ----------------------------------------------------
            RX_DATA: begin
                if (rx_baud_tick &&
                    (sample_cnt == SAMPLE_PERIOD_COUNT) &&
                    (bit_cnt == LAST_DATA_BIT)) begin

                    if (parity_enable) begin
                        next_state = RX_PARITY;
                    end
                    else begin
                        next_state = RX_STOP;
                    end
                end
            end


            // ----------------------------------------------------
            // PARITY
            // Sample parity bit
            // ----------------------------------------------------
            RX_PARITY: begin
                if (rx_baud_tick &&
                    (sample_cnt == SAMPLE_PERIOD_COUNT)) begin

                    next_state = RX_STOP;
                end
            end


            // ----------------------------------------------------
            // STOP
            // Receive one or two stop bits
            // ----------------------------------------------------
            RX_STOP: begin
                if (rx_baud_tick &&
                    (sample_cnt == SAMPLE_PERIOD_COUNT)) begin

                    if (!i_frame_mode || stop_cnt) begin
                        next_state = RX_IDLE;
                    end
                end
            end


            // ----------------------------------------------------
            // DEFAULT
            // ----------------------------------------------------
            default: begin
                next_state = RX_IDLE;
            end

        endcase
    end


    // ============================================================
    // FSM LAYER 3
    // OUTPUT / CONTROL LOGIC
    //
    // Decode FSM state into datapath control signals.
    // ============================================================

    always_comb begin

        sample_tick_en  = 1'b0;
        sample_terminal = 1'b0;

        data_sample_en   = 1'b0;
        parity_sample_en = 1'b0;
        stop_sample_en   = 1'b0;

        frame_complete   = 1'b0;


        case (current_state)

            // ----------------------------------------------------
            // IDLE
            // No datapath sampling operation
            // ----------------------------------------------------
            RX_IDLE: begin
                sample_tick_en = 1'b0;
            end


            // ----------------------------------------------------
            // START
            // Sample start bit after half-bit delay
            // ----------------------------------------------------
            RX_START: begin
                sample_tick_en = rx_baud_tick;

                if (rx_baud_tick &&
                    (sample_cnt == START_MID_COUNT)) begin

                    sample_terminal = 1'b1;
                end
            end


            // ----------------------------------------------------
            // DATA
            // Sample every 8 RX baud ticks
            // ----------------------------------------------------
            RX_DATA: begin
                sample_tick_en = rx_baud_tick;

                if (rx_baud_tick &&
                    (sample_cnt == SAMPLE_PERIOD_COUNT)) begin

                    sample_terminal = 1'b1;
                    data_sample_en  = 1'b1;
                end
            end


            // ----------------------------------------------------
            // PARITY
            // Sample parity bit
            // ----------------------------------------------------
            RX_PARITY: begin
                sample_tick_en = rx_baud_tick;

                if (rx_baud_tick &&
                    (sample_cnt == SAMPLE_PERIOD_COUNT)) begin

                    sample_terminal = 1'b1;
                    parity_sample_en = 1'b1;
                end
            end


            // ----------------------------------------------------
            // STOP
            // Sample stop bit(s)
            // ----------------------------------------------------
            RX_STOP: begin
                sample_tick_en = rx_baud_tick;

                if (rx_baud_tick &&
                    (sample_cnt == SAMPLE_PERIOD_COUNT)) begin

                    sample_terminal = 1'b1;
                    stop_sample_en  = 1'b1;

                    if (!i_frame_mode || stop_cnt) begin
                        frame_complete = 1'b1;
                    end
                end
            end


            // ----------------------------------------------------
            // DEFAULT
            // ----------------------------------------------------
            default: begin
                sample_tick_en = 1'b0;
            end

        endcase
    end


    // ============================================================
    // DATAPATH
    // SAMPLE COUNTER
    // Owns: sample_cnt
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            sample_cnt <= '0;
        end
        else if (!i_rx_en) begin
            sample_cnt <= '0;
        end
        else if (current_state == RX_IDLE) begin
            sample_cnt <= '0;
        end
        else if (sample_tick_en) begin

            if (sample_terminal) begin
                sample_cnt <= '0;
            end
            else begin
                sample_cnt <= sample_cnt + 3'd1;
            end
        end
    end


    // ============================================================
    // DATAPATH
    // DATA BIT COUNTER
    // Owns: bit_cnt
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            bit_cnt <= '0;
        end
        else if (!i_rx_en) begin
            bit_cnt <= '0;
        end
        else if (current_state == RX_IDLE) begin
            bit_cnt <= '0;
        end
        else if (data_sample_en) begin

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
    // RX DATA SHIFT BUFFER
    // Owns: rx_shift_buffer
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            rx_shift_buffer <= '0;
        end
        else if (!i_rx_en) begin
            rx_shift_buffer <= '0;
        end
        else if (data_sample_en) begin
            rx_shift_buffer[bit_cnt] <= rx_sync_data;
        end
    end


    // ============================================================
    // DATAPATH
    // STOP BIT COUNTER
    // Owns: stop_cnt
    //
    // frame_mode = 0 -> 1 stop bit
    // frame_mode = 1 -> 2 stop bits
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            stop_cnt <= 1'b0;
        end
        else if (!i_rx_en) begin
            stop_cnt <= 1'b0;
        end
        else if (current_state != RX_STOP) begin
            stop_cnt <= 1'b0;
        end
        else if (stop_sample_en) begin

            if (!i_frame_mode) begin
                stop_cnt <= 1'b0;
            end
            else if (!stop_cnt) begin
                stop_cnt <= 1'b1;
            end
            else begin
                stop_cnt <= 1'b0;
            end
        end
    end


    // ============================================================
    // DATAPATH
    // PARITY ERROR CHECK
    // Owns: parity_error_pending
    //
    // Stores parity result for the current frame.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            parity_error_pending <= 1'b0;
        end
        else if (!i_rx_en) begin
            parity_error_pending <= 1'b0;
        end
        else if (current_state == RX_IDLE) begin
            parity_error_pending <= 1'b0;
        end
        else if (parity_sample_en) begin

            case (i_parity_mode)

                2'b01: begin
                    parity_error_pending
                        <= rx_sync_data != (~^rx_shift_buffer);
                end

                2'b11: begin
                    parity_error_pending
                        <= rx_sync_data != (^rx_shift_buffer);
                end

                default: begin
                    parity_error_pending <= 1'b0;
                end

            endcase
        end
    end


    // ============================================================
    // DATAPATH
    // FRAME ERROR ACCUMULATION
    // Owns: frame_error_pending
    //
    // A low level at any required stop bit sets the error.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            frame_error_pending <= 1'b0;
        end
        else if (!i_rx_en) begin
            frame_error_pending <= 1'b0;
        end
        else if (current_state != RX_STOP) begin
            frame_error_pending <= 1'b0;
        end
        else if (stop_sample_en) begin

            if (!rx_sync_data) begin
                frame_error_pending <= 1'b1;
            end
        end
    end


    // ============================================================
    // DATAPATH
    // PARITY ERROR OUTPUT REGISTER
    // Owns: parity_error_reg
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            parity_error_reg <= 1'b0;
        end
        else if (!i_rx_en) begin
            parity_error_reg <= 1'b0;
        end
        else if (frame_complete) begin
            parity_error_reg <= parity_error_pending;
        end
    end


    // ============================================================
    // DATAPATH
    // FRAME ERROR OUTPUT REGISTER
    // Owns: frame_error_reg
    //
    // rx_sync_data is included because the final stop-bit sample
    // occurs in the same clock edge as frame_complete.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            frame_error_reg <= 1'b0;
        end
        else if (!i_rx_en) begin
            frame_error_reg <= 1'b0;
        end
        else if (frame_complete) begin

            frame_error_reg
                <= frame_error_pending || !rx_sync_data;
        end
    end


    // ============================================================
    // DATAPATH
    // RX HOLD BUFFER
    // Owns: rx_hold_buffer
    //
    // Commit received byte only when frame has no framing error.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            rx_hold_buffer <= '0;
        end
        else if (!i_rx_en) begin
            rx_hold_buffer <= '0;
        end
        else if (frame_complete) begin

            if (!(frame_error_pending || !rx_sync_data)) begin

                if (!rx_hold_valid || i_ready) begin
                    rx_hold_buffer <= rx_shift_buffer;
                end
            end
        end
    end


    // ============================================================
    // DATAPATH
    // RX HOLD VALID
    // Owns: rx_hold_valid
    //
    // New frame completion has priority over consuming old data.
    // ============================================================

    always_ff @(posedge clk) begin
        if (!rstn) begin
            rx_hold_valid <= 1'b0;
        end
        else if (!i_rx_en) begin
            rx_hold_valid <= 1'b0;
        end
        else if (frame_complete &&
                 !(frame_error_pending || !rx_sync_data) &&
                 (!rx_hold_valid || i_ready)) begin

            rx_hold_valid <= 1'b1;
        end
        else if (rx_hold_valid && i_ready) begin
            rx_hold_valid <= 1'b0;
        end
    end

endmodule
