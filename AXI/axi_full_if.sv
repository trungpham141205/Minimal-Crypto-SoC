interface axi_full_if #(
	parameter ADDR_WIDTH = 32,
 	parameter DATA_WIDTH = 32,
	parameter ID_WIDTH = 4,
	parameter WCHK_WIDTH = DATA_WIDTH / 8
)(
	input logic clk,
	input logic rstn
);

	//1. Write Address (AW)
	logic [ID_WIDTH-1:0]awid;
	logic awwakeup;
	logic [ADDR_WIDTH-1:0]awaddr;
	logic [7:0]awlen;
	logic [2:0]awsize;
	logic [1:0]awburst;
	logic awvalid;
	logic awready;
	logic [2:0]awprot;
	logic [3:0]awchk;
	
	//2. Write Data (W)
	logic [DATA_WIDTH-1:0]wdata;
	logic [WCHK_WIDTH-1:0]wstrb;
	logic wlast;
	logic wvalid;
	logic wready;
	logic [WCHK_WIDTH-1:0]wchk;

	//3. Response (B)
	logic [ID_WIDTH-1:0]bid;
	logic [1:0]bresp;
	logic bvalid;
	logic bready;
	logic bchk;

	//4. Read Address (AR)
	logic [ID_WIDTH-1:0]arid;
	logic arwakeup;
	logic [ADDR_WIDTH-1:0]araddr;
	logic [7:0]arlen;
	logic [2:0]arsize;
	logic [1:0]arburst;
	logic arvalid;
	logic arready;
	logic [2:0]arprot;
	logic [3:0]archk;

	//5. Read Data (R)
	logic [ID_WIDTH-1:0]rid;
	logic [DATA_WIDTH-1:0]rdata;
	logic [1:0]rresp;
	logic rlast;
	logic rvalid;
	logic rready;
	logic [3:0]rchk;

	//Modport Master
	modport master(
		input clk,
		input rstn,
		output awid, awwakeup, awaddr, awlen, awsize, awburst, awvalid, awprot, awchk, input awready,
		output wdata, wstrb, wlast, wvalid, wchk, input wready,
		output bready, input bid, bresp, bvalid, bchk,
		output arwakeup, arid, araddr, arlen, arsize, arburst, arvalid, arprot, archk, input arready,
		output rready, input rid, rdata, rresp, rlast, rvalid, rchk
	);
	
	//Modport Slave
	modport slave(
		input clk,
		input rstn,
		input awid, awwakeup, awaddr, awlen, awsize, awburst, awvalid, awprot, awchk, output awready,
                input wdata, wstrb, wlast, wvalid, wchk, output wready,
                input bready, output bid, bresp, bvalid, bchk,
                input arwakeup, arid, araddr, arlen, arsize, arburst, arvalid, arprot, archk, output arready,
                input rready, output rid, rdata, rresp, rlast, rvalid, rchk
	);

endinterface

	
