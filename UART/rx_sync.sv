module rx_sync (
    input logic clk,
    input logic rstn,
    input logic i_rx,
    output logic rx_sync_data
);
        
    logic rx_capture;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            rx_capture <= 1'b1;
            rx_sync_data <= 1'b1;
        end
        else begin
            rx_capture <= i_rx;
            rx_sync_data <= rx_capture;
        end
    end

endmodule
