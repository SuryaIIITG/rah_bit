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

    // Internal flags for controlling FIFO state
    reg fifo_empty_wr;  // Write side empty flag
    reg fifo_empty_rd;  // Read side empty flag

    reg [3:0] state = 0;  // State machine variable
    reg [3:0] prev_state = 0;
    reg [1:0] cnt = 0;    // Count variable for controlling FIFO behavior
    reg take_last_data = 0;

    // Write operation state machine
    always @(posedge clk_wr or posedge rst) begin
        if (rst) begin
            wr_ptr <= 4'd0;
            fifo_full <= 1'b0;
            count <= 4'd0;
            fifo_empty_wr <= 1'b1;
            state <= 0;
        end else begin
            case (state)
                0: begin
                    // Wait for write enable and space in FIFO
                    if (wr_en && count < 16) begin
                        fifo_mem[wr_ptr] <= data_in;
                        wr_ptr <= wr_ptr + 1;
                        count <= count + 1;
                        fifo_full <= (count == 15);
                        fifo_empty_wr <= 1'b0;  // FIFO is not empty after data write
                        state <= 1;
                    end
                end
                1: begin
                    // Handle transition after write
                    if (wr_en && count < 16) begin
                        state <= 0;
                    end
                end
            endcase
        end
    end

    // Read operation and block assembly
    always @(posedge clk_rd or posedge rst) begin
        if (rst) begin
            rd_ptr <= 4'd0;
            block_header <= 512'b0;
            block_ready <= 1'b0;
            fifo_empty_rd <= 1'b1;
            state <= 0;
        end else begin
            case (state)
                0: begin
                    block_ready <= 0;
                    if (count == 16) begin
                        // Assemble 512-bit block when FIFO is full
                        block_header <= {fifo_mem[0], fifo_mem[1], fifo_mem[2], fifo_mem[3], 
                                         fifo_mem[4], fifo_mem[5], fifo_mem[6], fifo_mem[7], 
                                         fifo_mem[8], fifo_mem[9], fifo_mem[10], fifo_mem[11], 
                                         fifo_mem[12], fifo_mem[13], fifo_mem[14], fifo_mem[15]};
                        block_ready <= 1'b1;
                        state <= 1;
                    end
                end
                1: begin
                    // Process block after it's ready
                    if (rd_en && block_ready) begin
                        rd_ptr <= 4'd0;
                        block_ready <= 0;
                        count <= 4'd0;
                        fifo_empty_rd <= (count == 0);  // FIFO is empty after read
                        state <= 0;
                    end
                end
            endcase
        end
    end

    // Combine read and write empty flags to assign to fifo_empty
    always @(*) begin
        fifo_empty = fifo_empty_wr & fifo_empty_rd;
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

module cvt (
    input clk_wr,
    input clk_rd,
    input valid_data_size_rah,
    input [31:0] data_size_rah,
    input data_queue_empty,
    input data_queue_almost_empty,
    input [9:0] fifo_occupants,
    input [31:0] data,
    output reg data_request = 0,

    input rd_enable,
    
    output cvt_data_queue_empty,
    output cvt_data_queue_almost_empty,
    output cvt_data_valid,
    output [47:0] cvt_data
);

    reg fifo_we = 0;
    reg [47:0] w_data = 0;
    reg [31:0] data_cnt = 0;
    reg [15:0] tmp_data = 0;
    reg [1:0] state = 0;

    async_fifo_256 af256 (
        .clk_wr(clk_wr),
        .clk_rd(clk_rd),
        .rst(1'b0),
        .wr_en(fifo_we),
        .data_in(w_data),
        .rd_en(rd_enable),
        .data_out(cvt_data),
        .data_valid(cvt_data_valid),
        .empty(cvt_data_queue_empty),
        .almost_empty(cvt_data_queue_almost_empty)
    );

    always @(posedge clk_wr) begin
        case (state)
            0: begin
                fifo_we <= 0;
                if (valid_data_size_rah) begin
                    data_cnt <= data_size_rah;
                    state <= 1;
                end
            end

            1: begin
                if (data_cnt > 4) begin
                    data_cnt <= data_cnt - 4;
                    w_data <= {data, 16'h0};
                    fifo_we <= 1;
                    state <= 2;
                end
            end

            2: begin
                fifo_we <= 1;
                w_data[15:0] <= data[31:16];
                tmp_data <= data[15:0];
                state <= 3;
            end

            3: begin
                w_data[47:32] <= tmp_data;
                w_data[31:0] <= data;
                fifo_we <= 1;
                state <= 0;
            end
        endcase
    end

endmodule
