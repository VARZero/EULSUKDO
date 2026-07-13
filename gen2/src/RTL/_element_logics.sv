`timescale 1ns/1ps

module regfile #(
    parameter  int DATA_WIDTH       = 32,
    parameter  int ENTRIES          = 16,
    parameter  int READ_CHANNEL     = 2,
    parameter  int WRITE_CHANNEL    = 2,

    localparam int ADDR_ENTRY       = $clog2(ENTRIES),

    localparam int READ_ADDR_WIDTH  = ADDR_ENTRY * READ_CHANNEL,
    localparam int READ_DATA_WIDTH  = DATA_WIDTH * READ_CHANNEL,
    localparam int WRITE_ADDR_WIDTH = ADDR_ENTRY * WRITE_CHANNEL,
    localparam int WRITE_DATA_WIDTH = DATA_WIDTH * WRITE_CHANNEL
) (
    input  logic clk,
    input  logic reset_n,
    
    input  logic [READ_ADDR_WIDTH-1:0]  i_read_addr,
    output logic [READ_DATA_WIDTH-1:0]  o_read_data,

    input  logic [WRITE_ADDR_WIDTH-1:0] i_write_addr,
    input  logic [WRITE_CHANNEL-1:0]    i_write_en,
    input  logic [WRITE_DATA_WIDTH-1:0] i_write_data
);

    logic [ADDR_ENTRY-1:0] raddr [0:READ_CHANNEL-1];
    logic [DATA_WIDTH-1:0] rdata [0:READ_CHANNEL-1];

    logic [ADDR_ENTRY-1:0] waddr [0:WRITE_CHANNEL-1];
    logic                  we    [0:WRITE_CHANNEL-1];
    logic [DATA_WIDTH-1:0] wdata [0:WRITE_CHANNEL-1];
    
    genvar read_chan;
    generate
        for (read_chan = 0; read_chan < READ_CHANNEL; read_chan = read_chan+1) begin : gen_read_bind
            assign raddr[read_chan] = i_read_addr[(ADDR_ENTRY*read_chan) +: ADDR_ENTRY];
            assign o_read_data[(DATA_WIDTH*read_chan) +: DATA_WIDTH] = rdata[read_chan];
        end
    endgenerate

    genvar write_chan;
    generate
        for (write_chan = 0; write_chan < WRITE_CHANNEL; write_chan = write_chan+1) begin : gen_write_bind
            assign waddr[write_chan] = i_write_addr[(ADDR_ENTRY*write_chan) +: ADDR_ENTRY];
            assign we   [write_chan] = i_write_en  [write_chan];
            assign wdata[write_chan] = i_write_data[(DATA_WIDTH*write_chan) +: DATA_WIDTH];
        end
    endgenerate

    logic [DATA_WIDTH-1:0] reg_mem [0:ENTRIES-1];

    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            for (int reg_init = 0; reg_init < ENTRIES; reg_init = reg_init + 1) begin
                reg_mem[reg_init] <= 0;
            end
        end
        else begin
            for (int reg_write = 0; reg_write < ENTRIES; reg_write = reg_write + 1) begin
                for (int reg_update = 0; reg_update < WRITE_CHANNEL; reg_update = reg_update + 1) begin
                    if ( we[reg_update] && (waddr[reg_update] == reg_write) ) begin
                        reg_mem[ reg_write ] <= wdata[reg_update];
                    end
                end
            end
        end
    end

    always_comb begin
        for (int reg_read = 0; reg_read < READ_CHANNEL; reg_read = reg_read + 1) begin
            rdata[reg_read] = reg_mem[ raddr[reg_read] ];
        end
    end

endmodule


