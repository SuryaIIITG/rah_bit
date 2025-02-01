module top_miner (
    input clk_wr,        // Write clock
    input clk_rd,        // Read clock
    input rst,           // Reset signal
    input wr_en,         // Write enable for input FIFO
    input [31:0] data_in, // 32-bit input data for block header
    input miner_start,   // Start signal for miner
    output [31:0] data_out, // 32-bit output data from hash FIFO
    output data_valid    // Valid signal for output data
);

    wire [511:0] block_header;
    wire block_ready;
    reg rd_en_fifo;

    wire [255:0] hash1_out;
    wire output_valid;
    reg rd_en_hash;

    // FIFO for collecting 32-bit data into 512-bit block
    async_fifo_512 fifo_input (
        .clk_wr(clk_wr),
        .clk_rd(clk_rd),
        .rst(rst),
        .wr_en(wr_en),
        .data_in(data_in),
        .rd_en(rd_en_fifo),
        .block_header(block_header),
        .block_ready(block_ready)
    );

    // Miner instantiation
    miner miner_inst (
        .clk(clk_rd),
        .rst(rst),
        .input_valid(block_ready && miner_start),
        .block_header(block_header),
        .hash1_out(hash1_out),
        .output_valid(output_valid)
    );

    // FIFO for breaking 256-bit hash into 32-bit chunks
    async_fifo_256 fifo_output (
        .clk_wr(clk_rd),
        .clk_rd(clk_wr),
        .rst(rst),
        .wr_en(output_valid),
        .hash_in(hash1_out),
        .rd_en(rd_en_hash),
        .data_out(data_out),
        .data_valid(data_valid)
    );

    // Read enable logic
    always @(posedge clk_rd or posedge rst) begin
        if (rst) begin
            rd_en_fifo <= 1'b0;
            rd_en_hash <= 1'b0;
        end else begin
            rd_en_fifo <= block_ready && miner_start;  // Read block header when miner is ready
            rd_en_hash <= output_valid;  // Read hash output when available
        end
    end

endmodule
