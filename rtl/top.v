`include "rah_var_defs.vh"

module top (
/* Clocks of MIPI TX and RX parallel interfaces */
    input                       rx_pixel_clk,
    input                       tx_pixel_clk,
    input                       tx_vga_clk,

/* Signals used by the MIPI RX Interface Designer instance */
    input                       my_mipi_rx_VALID,
    input [3:0]                 my_mipi_rx_HSYNC,
    input [3:0]                 my_mipi_rx_VSYNC,
    input [63:0]                my_mipi_rx_DATA,
    input [5:0]                 my_mipi_rx_TYPE,
    input [1:0]                 my_mipi_rx_VC,
    input [3:0]                 my_mipi_rx_CNT,
    input [17:0]                my_mipi_rx_ERROR,
    input                       my_mipi_rx_ULPS_CLK,
    input [3:0]                 my_mipi_rx_ULPS,

    output                      my_mipi_rx_DPHY_RSTN,
    output                      my_mipi_rx_RSTN,
    output                      my_mipi_rx_CLEAR,
    output [1:0]                my_mipi_rx_LANES,
    output [3:0]                my_mipi_rx_VC_ENA,

/* Signals used by the MIPI TX Interface Designer instance */
    output                      my_mipi_tx_DPHY_RSTN,
    output                      my_mipi_tx_RSTN,
    output                      my_mipi_tx_VALID,
    output                      my_mipi_tx_HSYNC,
    output                      my_mipi_tx_VSYNC,
    output [63:0]               my_mipi_tx_DATA,
    output [5:0]                my_mipi_tx_TYPE,
    output [1:0]                my_mipi_tx_LANES,
    output                      my_mipi_tx_FRAME_MODE,
    output [15:0]               my_mipi_tx_HRES,
    output [1:0]                my_mipi_tx_VC,
    output [3:0]                my_mipi_tx_ULPS_ENTER,
    output [3:0]                my_mipi_tx_ULPS_EXIT,
    output                      my_mipi_tx_ULPS_CLK_ENTER,
    output                      my_mipi_tx_ULPS_CLK_EXIT,
    
/* Connections to the GPIOs */
    input                       uart_rx_pin,
    output                      uart_tx_pin
);

parameter RAH_PACKET_WIDTH = 48;
parameter ACTIVE_VID_WIDTH = 1280;
parameter ACTIVE_VID_HEIGHT = 1024;


/* Rah Decoder definition for multiple Apps */
assign my_mipi_rx_DPHY_RSTN = 1'b1;
assign my_mipi_rx_RSTN = 1'b1;
assign my_mipi_rx_CLEAR = 1'b0;
assign my_mipi_rx_LANES = 2'b11;
assign my_mipi_rx_VC_ENA = 4'b0001;

wire [`TOTAL_APPS-1:0] rd_clk;
wire [`TOTAL_APPS-1:0] request_data;

wire [`TOTAL_APPS-1:0] data_queue_empty;
wire [`TOTAL_APPS-1:0] data_queue_almost_empty;
wire [`TOTAL_APPS-1:0] rd_error;

wire [(`TOTAL_APPS*RAH_PACKET_WIDTH)-1:0] rd_data;

wire [RAH_PACKET_WIDTH-1:0] aligned_data;
wire end_of_packet;

/* Align the data for the decoding process */
data_aligner #(
    .DATA_WIDTH(RAH_PACKET_WIDTH)
) da (
    .clk            (rx_pixel_clk),

    .mipi_data      (my_mipi_rx_DATA),
    .end_of_packet  (end_of_packet),

    .aligned_data   (aligned_data)
);

/* Depacketizing the recevied data */
rah_decoder #(
    .DATA_WIDTH(RAH_PACKET_WIDTH)
) rd (
    /* rah raw input variables */
    .clk                        (rx_pixel_clk),

    .mipi_data                  (aligned_data),
    .mipi_rx_valid              (my_mipi_rx_VALID),

    .rd_clk                     (rd_clk),
    .request_data               (request_data),

    .end_of_packet              (end_of_packet),
    .data_queue_empty           (data_queue_empty),
    .data_queue_almost_empty    (data_queue_almost_empty),
    .rd_data                    (rd_data),
    .error                      (rd_error)
);

/* Send data to processor */
wire [`TOTAL_APPS-1:0] wr_clk;
wire [(`TOTAL_APPS*RAH_PACKET_WIDTH)-1:0] wr_data;
wire [`TOTAL_APPS-1:0] write_apps_data;

wire vid_gen_clk;
assign vid_gen_clk = tx_vga_clk;

wire mipi_out_rst;
wire mipi_valid;
wire [RAH_PACKET_WIDTH-1:0] mipi_out_data;
wire hsync;
wire vsync;

rah_encoder #(
    .WIDTH(ACTIVE_VID_WIDTH),
    .HEIGHT(ACTIVE_VID_HEIGHT),
    .DATA_WIDTH(RAH_PACKET_WIDTH)
) re (
    .clk                    (tx_pixel_clk),
    .vid_gen_clk            (vid_gen_clk),
    .send_data              (write_apps_data),
    .wr_clk                 (wr_clk),
    .wr_data                (wr_data),
    .mipi_rst               (mipi_out_rst),
    .mipi_valid             (mipi_valid),
    .mipi_data              (mipi_out_data),
    .hsync_patgen           (hsync),
    .vsync_patgen           (vsync)
);

/* SHA Bridge */
wire [`TOTAL_APPS-1:0] write_apps_data;   
wire [RAH_PACKET_WIDTH-1:0] wr_data;     
wire w_rst, w_input_valid, w_output_valid;
wire [511:0] w_block_header;
wire [255:0] w_hash1_out, w_hash_result;

/* FIFO Clocks */
assign wr_clk[`MINER] = rx_pixel_clk;
assign rd_clk[`MINER] = rx_pixel_clk;

/* RAH-SHA Bridge Module Instantiation */
rah_sha_bridge bridge (
    .clk                (rx_pixel_clk),                                 // Clock signal
    .rst                (w_rst),                                          // Reset signal
    .wr_fifo_empty      (data_queue_empty[`MINER]),                     // FIFO empty signal
    .wr_fifo_a_empty    (data_queue_almost_empty[`MINER]),              // FIFO almost empty signal
    .wr_fifo_read_data  (rd_data[`MINER * RAH_PACKET_WIDTH +: RAH_PACKET_WIDTH]), // FIFO read data
    .wr_fifo_read_en    (request_data[`MINER]),                         // FIFO read enable
    .input_valid        (w_input_valid),                                // Input valid signal for miner
    .block_header       (w_block_header),                               // Block header for miner input
    .hash1_out          (w_hash1_out),                                  // Intermediate hash output from miner
    .output_valid       (w_output_valid),                               // Output valid signal from miner
    .pp_rd_fifo_en      (write_apps_data[`MINER]),                      // Enable signal for post-processing FIFO
    .pp_rd_fifo_data    (wr_data)                                       // Data written to post-processing FIFO
);


/* Miner Module Instantiation */
miner miner_inst (
    .clk            (rx_pixel_clk),                                    // Clock signal
    .rst            (w_rst),                                             // Reset signal
    .input_valid    (w_input_valid),                                   // Input valid signal from bridge
    .block_header   (w_block_header),                                  // Block header data from bridge
    .hash1_out      (w_hash1_out),                                     // Intermediate hash output
    .output_valid   (w_output_valid)                                   // Output valid signal
);


assign my_mipi_tx_DPHY_RSTN = ~mipi_out_rst;
assign my_mipi_tx_RSTN = ~mipi_out_rst;
assign my_mipi_tx_VALID = mipi_valid;
assign my_mipi_tx_HSYNC = hsync;
assign my_mipi_tx_VSYNC = vsync;
assign my_mipi_tx_DATA = mipi_out_data;
assign my_mipi_tx_TYPE = 6'h24;
assign my_mipi_tx_LANES = 2'b11;
assign my_mipi_tx_FRAME_MODE = 1'b0;
assign my_mipi_tx_HRES = ACTIVE_VID_WIDTH;
assign my_mipi_tx_VC = 2'b00;
assign my_mipi_tx_ULPS_ENTER = 4'b0000;
assign my_mipi_tx_ULPS_EXIT = 4'b0000;
assign my_mipi_tx_ULPS_CLK_ENTER = 1'b0;
assign my_mipi_tx_ULPS_CLK_EXIT = 1'b0;

endmodule
