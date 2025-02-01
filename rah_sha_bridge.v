module rah_sha_bridge (
    input wire clk,
    input wire wr_fifo_empty,
    input wire wr_fifo_a_empty,
    input wire [47:0] wr_fifo_read_data,
    output reg wr_fifo_read_en,
    
    input wire output_valid,
    input wire [255:0] hash1_out,
    input wire [255:0] hash_result,

    output reg input_valid,
    output reg [511:0] block_header,

    output reg pp_rd_fifo_en,
    output reg [47:0] pp_rd_fifo_data,
    output reg rst // Reset depends on wr_fifo_empty
);

// Parameters
parameter DATA_WIDTH = 512;
parameter BYTE_SIZE = 11;
parameter FIFO_CHUNK_SIZE = 48;
parameter EMPTY_CYCLES = 16; // Number of cycles to wait before asserting reset

// Registers
reg [DATA_WIDTH-1:0] r_block_header = 0;
reg [3:0] byte_counter = 0;
reg [2:0] rd_byte_counter = 0;
reg data_ready = 0;
reg [2:0] current_state, next_state;
reg [3:0] empty_counter = 0; // Counter for wr_fifo_empty debounce
reg [1:0] data_storage_state = 0; // State to track data storage completion

// FSM States
localparam IDLE            = 3'b000;
localparam WAIT            = 3'b100;
localparam READ_FIFO       = 3'b001;
localparam PROCESS_DATA    = 3'b010;
localparam TRANSFER_HASH   = 3'b011;

// Assign reset based on wr_fifo_empty with debounce mechanism
always @(posedge clk) begin
    if (wr_fifo_empty) begin
        if (empty_counter < EMPTY_CYCLES - 1) begin
            empty_counter <= empty_counter + 1;
            rst <= 0; // Keep reset deasserted while waiting
        end else begin
            rst <= 1; // Assert reset after debounce period
        end
    end else begin
        empty_counter <= 0;
        rst <= 0; // Deassert reset when wr_fifo_empty is low
    end
end

// FSM Logic
always @(posedge clk or posedge rst) begin
    if (rst)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// Next State Logic
always @(*) begin
    wr_fifo_read_en = 0;
    input_valid = 0;
    pp_rd_fifo_en = 0;
    next_state = current_state;

    case (current_state)
        IDLE: begin
            if (!wr_fifo_empty) begin
                next_state = WAIT;
                wr_fifo_read_en = 1;
            end
        end
        
        WAIT: next_state <= READ_FIFO;

        READ_FIFO: begin
            if (byte_counter == 11) begin
                next_state = PROCESS_DATA;
                data_ready = 1;
                data_storage_state = 1; // Indicate data storage is complete
            end else begin
                wr_fifo_read_en = 1;
            end
        end

        PROCESS_DATA: begin
            if (data_ready && data_storage_state == 1) begin
                input_valid = 1; // Enable input_valid only after data is stored
                next_state = TRANSFER_HASH;
            end
        end

        TRANSFER_HASH: begin
            if (output_valid) begin
                pp_rd_fifo_en = 1;
                next_state = IDLE;
            end
        end
    endcase
end

// Read and assemble block header
always @(posedge clk) begin
    if (wr_fifo_read_en) begin
        case (byte_counter)
            10: r_block_header[31:0]   <= wr_fifo_read_data[47:16];
            9:  r_block_header[79:32]  <= wr_fifo_read_data;
            8:  r_block_header[127:80]  <= wr_fifo_read_data;
            7:  r_block_header[175:128] <= wr_fifo_read_data;
            6:  r_block_header[223:176] <= wr_fifo_read_data;
            5:  r_block_header[271:224] <= wr_fifo_read_data;
            4:  r_block_header[319:272] <= wr_fifo_read_data;
            3:  r_block_header[367:320] <= wr_fifo_read_data;
            2:  r_block_header[415:368] <= wr_fifo_read_data;
            1:  r_block_header[463:416] <= wr_fifo_read_data; 
            0:  r_block_header[511:464] <= wr_fifo_read_data;
            default: r_block_header <= 512'b0;
        endcase
        
        if (byte_counter <= 10) begin
            byte_counter <= byte_counter + 1;
        end else begin
            byte_counter <= 0;
        end
    end
end

// Assign block header after assembly is complete and input_valid is enabled
always @(posedge clk or posedge rst) begin
    if (rst)
        block_header <= 512'b0;
    else if (current_state == PROCESS_DATA && data_ready && data_storage_state == 1)
        block_header <= r_block_header;
end

// Read pp_rd_fifo_data in 48-bit chunks
always @(posedge clk) begin
    if (pp_rd_fifo_en) begin
        case (rd_byte_counter)
            0: pp_rd_fifo_data <= hash1_out[47:0];
            1: pp_rd_fifo_data <= hash1_out[95:48];
            2: pp_rd_fifo_data <= hash1_out[143:96];
            3: pp_rd_fifo_data <= hash1_out[191:144];
            4: pp_rd_fifo_data <= hash1_out[239:192];
            5: pp_rd_fifo_data <= hash1_out[255:240];
        endcase

        if (rd_byte_counter == 5)
            rd_byte_counter <= 0;
        else
            rd_byte_counter <= rd_byte_counter + 1;
    end
end

endmodule
