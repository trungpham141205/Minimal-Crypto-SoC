module uart_core (
    input  logic        clk,
    input  logic        rstn,

    input  logic [15:0] i_baudrate,
    input  logic [1:0]  i_parity_mode,
    input  logic        i_frame_mode,
    input  logic        i_tx_en,
    input  logic        i_rx_en,

    input  logic [7:0]  i_data,
    input  logic        i_data_valid,
    output logic        o_ready,
    output logic        o_tx,

    input  logic        i_rx,
    output logic [7:0]  o_data,
    output logic        o_data_valid,
    input  logic        i_ready,

    output logic        o_parity_err,
    output logic        o_frame_err
);

    logic tx_baud_tick;
    logic rx_baud_tick;
    logic rx_sync_data;

    baud_gen baud_gen_inst (
        .clk          (clk),
        .rstn         (rstn),
        .i_baudrate   (i_baudrate),
        .i_tx_en      (i_tx_en),
        .i_rx_en      (i_rx_en),
        .tx_baud_tick (tx_baud_tick),
        .rx_baud_tick (rx_baud_tick)
    );

    rx_sync rx_sync_inst (
        .clk          (clk),
        .rstn         (rstn),
        .i_rx         (i_rx),
        .rx_sync_data (rx_sync_data)
    );

    uart_tx uart_tx_inst (
        .clk           (clk),
        .rstn          (rstn),
        .i_tx_en       (i_tx_en),
        .i_parity_mode (i_parity_mode),
        .i_frame_mode  (i_frame_mode),
        .tx_baud_tick  (tx_baud_tick),
        .i_data        (i_data),
        .i_data_valid  (i_data_valid),
        .o_ready       (o_ready),
        .o_tx          (o_tx)
    );

    uart_rx uart_rx_inst (
        .clk           (clk),
        .rstn          (rstn),
        .i_rx_en       (i_rx_en),
        .i_parity_mode (i_parity_mode),
        .i_frame_mode  (i_frame_mode),
        .rx_baud_tick  (rx_baud_tick),
        .rx_sync_data  (rx_sync_data),
        .o_data        (o_data),
        .o_data_valid  (o_data_valid),
        .i_ready       (i_ready),
        .o_parity_err  (o_parity_err),
        .o_frame_err   (o_frame_err)
    );

endmodule
