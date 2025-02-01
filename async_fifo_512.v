module async_fifo_512 (
    input clk_wr,           // Write clock
    input clk_rd,           // Read clock
    input rst,              // Asynchronous reset
    input wr_en,            // Write enable
    input [31:0] data_in,   // 32-bit input data
    input rd_en,            // Read enable (from miner)
    output reg [511:0] block_header, // 512-bit output
    output reg block_ready, // Signal indicating full 512-bit block is available
    output reg fifo_full,   // FIFO full flag
    output reg fifo_empty   // FIFO empty flag
);

    reg [31:0] fifo_mem [0:15];  // 16x32-bit FIFO storage
    reg [3:0] wr_ptr;  // Write pointer (4-bit for 16 locations)
    reg [3:0] rd_ptr;  // Read pointer (4-bit for 16 locations)
    reg [3:0] count;   // Track stored words

    // Internal signals to manage empty flags separately
    reg fifo_empty_wr;  // Write side empty flag
    reg fifo_empty_rd;  // Read side empty flag

    // Write operation
    always @(posedge clk_wr or posedge rst) begin
        if (rst) begin
            wr_ptr <= 4'd0;
            fifo_full <= 1'b0;
            count <= 4'd0;
            fifo_empty_wr <= 1'b1;  // Reset write-side empty flag at reset
        end else if (wr_en && !fifo_full) begin
            fifo_mem[wr_ptr] <= data_in;
            wr_ptr <= wr_ptr + 1;
            count <= count + 1;
            fifo_full <= (count == 4'd15);
            //fifo_empty_wr <= 1'b0;  // FIFO is not empty once we write data
        end
    end

    // Read operation and 512-bit assembly
    always @(posedge clk_rd or posedge rst) begin
        if (rst) begin
            rd_ptr <= 4'd0;
            block_header <= 512'b0;
            block_ready <= 1'b0;
            fifo_empty_rd <= 1'b1;  // Reset read-side empty flag on reset
        end else if (!block_ready && count == 4'd15) begin  // Change from 4'd16 to 4'd15
            // Assemble 512-bit block
            block_header <= {fifo_mem[0], fifo_mem[1], fifo_mem[2], fifo_mem[3], 
                             fifo_mem[4], fifo_mem[5], fifo_mem[6], fifo_mem[7], 
                             fifo_mem[8], fifo_mem[9], fifo_mem[10], fifo_mem[11], 
                             fifo_mem[12], fifo_mem[13], fifo_mem[14], fifo_mem[15]};
            block_ready <= 1'b1;
            fifo_empty_rd <= (count == 4'd0);  // Set FIFO empty flag after block is ready
        end else if (rd_en && block_ready) begin
            // Miner has read the block, reset FIFO and block_ready
            rd_ptr <= 4'd0;
            block_ready <= 1'b0;
            count <= 4'd0;
            fifo_empty_rd <= (count == 4'd0);  // Set FIFO empty flag after read
        end
    end

    // Combine read and write empty flags to assign to fifo_empty
    always @(*) begin
        fifo_empty = fifo_empty_wr & fifo_empty_rd;  // FIFO is empty when both flags are set
    end

    // Synchronizer for fifo_empty signal to read clock domain
    reg fifo_empty_sync_rd;

    always @(posedge clk_rd or posedge rst) begin
        if (rst)
            fifo_empty_sync_rd <= 1'b1;
        else
            fifo_empty_sync_rd <= fifo_empty;
    end

endmodule


module async_fifo_256 (
    input clk_wr,           // Write clock
    input clk_rd,           // Read clock
    input rst,              // Asynchronous reset
    input wr_en,            // Write enable
    input [255:0] hash_in,  // 256-bit input data from miner
    input rd_en,            // Read enable
    output reg [31:0] data_out, // 32-bit output
    output reg data_valid   // Indicates valid output data
);

    reg [255:0] fifo_reg;   // 256-bit register storage
    reg [2:0] rd_ptr;       // Read pointer for 8x32-bit chunks

    // Write operation
    always @(posedge clk_wr or posedge rst) begin
        if (rst) begin
            fifo_reg <= 256'b0;
        end else if (wr_en) begin
            fifo_reg <= hash_in;
        end
    end

    // Read operation
    always @(posedge clk_rd or posedge rst) begin
        if (rst) begin
            rd_ptr <= 3'd0;
            data_valid <= 1'b0;
        end else if (rd_en && rd_ptr < 8) begin
            data_out <= fifo_reg[rd_ptr*32 +: 32]; // Extract 32-bit chunks
            rd_ptr <= rd_ptr + 1;
            data_valid <= 1'b1;
        end else begin
            data_valid <= 1'b0;
        end
    end

endmodule
