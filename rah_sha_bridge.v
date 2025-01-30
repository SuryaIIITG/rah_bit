module rah_sha_bridge (
    input wire clk,                              // Clock signal
    input wire wr_fifo_empty,                   // FIFO empty signal
    input wire wr_fifo_a_empty,                 // FIFO almost empty signal
    input wire [47:0] wr_fifo_read_data,        // FIFO read data (now 48 bits)
    output wire wr_fifo_read_en,                // FIFO read enable signal
    
    input wire output_valid,                    // Output valid from the miner
    input wire [255:0] hash1_out,               // Intermediate hash output from the miner
    input wire [255:0] hash_result,             // Final hash result from the miner

    output wire input_valid,                    // Input valid signal
    output wire [511:0] block_header,           // Block header for miner input

    output wire pp_rd_fifo_en,                  // Enable for post-processing FIFO
    output reg [47:0] pp_rd_fifo_data,          // Data for post-processing FIFO (48 bits)
    output wire rst                              // Reset signal (output instead of input)
);

// Parameters
parameter RESET_THRESHOLD = 5000000;

// Registers
reg [511:0] r_block_header = 0;   // Register to hold block header
reg r_fifo_read_en = 0;           // Register for FIFO read enable
reg [23:0] reset_counter = 0;     // Reset counter
reg [3:0] byte_counter = 0;       // Byte counter for block header assembly
reg block_header_ready = 0;       // Flag to indicate block header is ready
reg r_input_en = 0;               // Input enable signal
reg start_transfer = 0;           // Transfer start flag
reg [2:0] rd_byte_counter = 0;    // Counter for 48-bit chunk read from hash output
reg [255:0] r_hash_out = 0;       // Register to store intermediate hash output

// FIFO read control
always @(posedge clk) begin
    if (!wr_fifo_empty && !block_header_ready) begin
        r_fifo_read_en <= 1;
    end else begin
        r_fifo_read_en <= 0;
    end 

    if (r_fifo_read_en) begin
        case (byte_counter)
            10: r_block_header[47:0]   <= wr_fifo_read_data;
            9:  r_block_header[95:48]  <= wr_fifo_read_data;
            8:  r_block_header[143:96] <= wr_fifo_read_data;
            7:  r_block_header[191:144] <= wr_fifo_read_data;
            6:  r_block_header[239:192] <= wr_fifo_read_data;
            5:  r_block_header[287:240] <= wr_fifo_read_data;
            4:  r_block_header[335:288] <= wr_fifo_read_data;
            3:  r_block_header[383:336] <= wr_fifo_read_data;
            2:  r_block_header[431:384] <= wr_fifo_read_data;
            1:  r_block_header[479:432] <= wr_fifo_read_data;
            0:  r_block_header[511:480] <= wr_fifo_read_data;
        endcase
        
        if (byte_counter == 10) begin
            block_header_ready <= 1;
            byte_counter <= 0;
            r_input_en < = 1;
        end else begin
            byte_counter <= byte_counter + 1;
        end
    end
end

// Hash Output Processing
always @(posedge clk) begin
    if (output_valid) begin
        case (rd_byte_counter)
            5: pp_rd_fifo_data <= hash1_out[47:0];
            4: pp_rd_fifo_data <= hash1_out[95:48];
            3: pp_rd_fifo_data <= hash1_out[143:96];
            2: pp_rd_fifo_data <= hash1_out[191:144];
            1: pp_rd_fifo_data <= hash1_out[239:192];
            0: pp_rd_fifo_data <= hash1_out[255:240];
        endcase
        
        if (rd_byte_counter == 5) begin
            start_transfer <= 0;
            rd_byte_counter <= 0;
        end else begin
            rd_byte_counter <= rd_byte_counter + 1;
        end
    end
end

// Reset logic
always @(posedge clk) begin
    if (byte_counter != 0 || r_fifo_read_en) begin
        reset_counter <= reset_counter + 1;
    end else begin
        reset_counter <= 0;
    end
end

// Output assignments
assign wr_fifo_read_en = r_fifo_read_en;
assign input_valid = r_input_en;
assign block_header = r_block_header;
assign pp_rd_fifo_en = start_transfer;
assign rst = (reset_counter > RESET_THRESHOLD) ? 1'b1 : 1'b0;

endmodule
