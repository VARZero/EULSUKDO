`timescale 1ns/1ps

module regfile #(
    parameter  int                    DATA_WIDTH    = 32,
    parameter  int                    ENTRIES       = 16,
    parameter  int                    READ_CHANNEL  = 2,
    parameter  int                    WRITE_CHANNEL = 2,
    parameter  logic [DATA_WIDTH-1:0] INITIAL_VALUE = 0,

    localparam int ADDR_ENTRY       = $clog2(ENTRIES),

    localparam int READ_ADDR_WIDTH  = ADDR_ENTRY * READ_CHANNEL,
    localparam int READ_DATA_WIDTH  = DATA_WIDTH * READ_CHANNEL,
    localparam int WRITE_ADDR_WIDTH = ADDR_ENTRY * WRITE_CHANNEL,
    localparam int WRITE_DATA_WIDTH = DATA_WIDTH * WRITE_CHANNEL
) (
    input  logic clk,
    input  logic reset_n,
    
    input  logic                        i_flush,
    
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
                reg_mem[reg_init] <= INITIAL_VALUE;
            end
        end
        else if (i_flush) begin
            for (int reg_init = 0; reg_init < ENTRIES; reg_init = reg_init + 1) begin
                reg_mem[reg_init] <= INITIAL_VALUE;
            end
        end
        else begin
            for (int reg_update = 0; reg_update < WRITE_CHANNEL; reg_update = reg_update + 1) begin
                if ( we[reg_update] ) begin
                    reg_mem[ waddr[reg_update] ] <= wdata[reg_update];
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

module bram_custom #(
    parameter  int                    DATA_WIDTH    = 32,
    parameter  int                    ENTRIES       = 16,

    localparam int ADDR_ENTRY       = $clog2(ENTRIES),

    localparam int READ_ADDR_WIDTH  = ADDR_ENTRY,
    localparam int READ_DATA_WIDTH  = DATA_WIDTH,
    localparam int WRITE_ADDR_WIDTH = ADDR_ENTRY,
    localparam int WRITE_DATA_WIDTH = DATA_WIDTH
) (
    input  logic clk,
    
    input  logic [READ_ADDR_WIDTH-1:0]  i_read_addr,
    output logic [READ_DATA_WIDTH-1:0]  o_read_data,

    input  logic [WRITE_ADDR_WIDTH-1:0] i_write_addr,
    input  logic                        i_write_en,
    input  logic [WRITE_DATA_WIDTH-1:0] i_write_data
);
    logic [DATA_WIDTH-1:0] mem [0:ENTRIES-1];

    always_ff @(posedge clk) begin
        if (i_write_en) begin
            mem[i_write_addr] <= i_write_data;
        end

        o_read_data <= mem[i_read_addr];
    end

endmodule

module gather_demux #(
    parameter  int DATA_WIDTH  = 32,
    parameter  int DEMUXING    = 8,

    localparam int DEMUX_WIDTH = $clog2(DEMUXING),
    localparam int DEMUX_OUT   = DATA_WIDTH*DEMUXING
) (
    input  logic [DATA_WIDTH-1:0]  i_data,
    input  logic [DEMUX_WIDTH-1:0] i_sel,
    output logic [DEMUX_OUT-1:0]   o_demux
);
    always_comb begin
        o_demux = 0;

        for (int demux_pos = 0; demux_pos < DEMUXING; demux_pos = demux_pos+1) begin
            if (demux_pos == i_sel) begin
                o_demux[(DATA_WIDTH*demux_pos) +: DATA_WIDTH] = i_data;
            end
        end
    end

endmodule

module gather_position #(
    parameter  int ENTRIES               = 8,

    localparam int ENTRIES_WIDTH         = $clog2(ENTRIES),
    localparam int GATHER_POSITION_WIDTH = ENTRIES*ENTRIES_WIDTH
) (
    input  logic [ENTRIES-1:0]               i_valid,
    output logic [GATHER_POSITION_WIDTH-1:0] o_positions,
    output logic [ENTRIES-1:0]               o_valid
);
    function automatic logic [GATHER_POSITION_WIDTH-1:0] get_positions (
        input  logic [ENTRIES-1:0] in_valid
    );
        logic [GATHER_POSITION_WIDTH-1:0] out_positions;
        logic [ENTRIES_WIDTH-1:0]         now_position;

        out_positions = 0;
        now_position = 0;

        for (int check_entry = 0; check_entry < ENTRIES; check_entry = check_entry+1) begin
            if ( in_valid[check_entry] ) begin
                out_positions[(ENTRIES_WIDTH*check_entry) +: ENTRIES_WIDTH] = now_position;
                now_position = now_position+1;
            end
        end

        return out_positions;
    endfunction

    function automatic logic [ENTRIES-1:0] gather_valid (
        input  logic [ENTRIES-1:0] in_valid
    );
        logic [ENTRIES-1:0]       out_valid;
        logic [ENTRIES_WIDTH-1:0] now_position;

        out_valid    = 0;
        now_position = 0;

        for (int check_valid = 0; check_valid < ENTRIES; check_valid = check_valid+1) begin
            if ( in_valid[check_valid] ) begin
                out_valid[now_position] = 1'b1;
                now_position = now_position+1;
            end
        end

        return out_valid;
    endfunction

    assign o_positions = get_positions(i_valid);
    assign o_valid     = gather_valid (i_valid);

endmodule

module valid_gather #(
    parameter  int DATA_WIDTH  = 32,
    parameter  int ENTRIES     = 8,

    localparam int INOUT_WIDTH = DATA_WIDTH*ENTRIES
) (
    input  logic [INOUT_WIDTH-1:0] i_data,
    input  logic [ENTRIES-1:0]     i_valid,
    output logic [ENTRIES-1:0]     o_valid,
    output logic [INOUT_WIDTH-1:0] o_data
);
    localparam int ENTRIES_WIDTH         = $clog2(ENTRIES);
    localparam int GATHER_POSITION_WIDTH = ENTRIES*ENTRIES_WIDTH;

    logic [GATHER_POSITION_WIDTH-1:0] positions_list;
    logic [ENTRIES_WIDTH-1:0] position_array [0:ENTRIES-1];

    logic [INOUT_WIDTH-1:0] out_array [0:ENTRIES-1];

    gather_position #(
        .ENTRIES (ENTRIES)
    ) U_GATHER_POSITION (
        .i_valid     (i_valid),
        .o_positions (positions_list),
        .o_valid     (o_valid)
    );

    genvar position;
    generate
        for (position = 0; position < ENTRIES; position = position+1) begin
            assign position_array[position] = positions_list[(ENTRIES_WIDTH*position) +: ENTRIES_WIDTH];
        end

        for (position = 0; position < ENTRIES; position = position+1) begin
            gather_demux #(
                .DATA_WIDTH (DATA_WIDTH),
                .DEMUXING   (ENTRIES)
            ) U_GATHER_DEMUX (
                .i_data (i_data[(DATA_WIDTH*position) +: DATA_WIDTH]),
                .i_sel  (position_array[position]),
                .o_demux(out_array[position])
            );
        end
    
    endgenerate

    always_comb begin
        o_data = 0;
        for (int pos = 0; pos < ENTRIES; pos = pos+1) begin
            o_data |= (i_valid[pos])? out_array[pos] : 0;
        end
    end

endmodule

module fifo_control #(
    parameter  int FIFO_DEPTH  = 32,
    parameter  int READ_DELAY  = 0, // 0 is False, 1 is True

    localparam int WIDTH_DEPTH = $clog2(FIFO_DEPTH)
) (
    input  logic clk,
    input  logic reset_n,

    input  logic i_flush,
    input  logic i_push,
    input  logic i_pop,
    output logic o_empty,
    output logic o_full,

    output logic [WIDTH_DEPTH-1:0] o_push_addr,
    output logic [WIDTH_DEPTH-1:0] o_pop_addr,

    output logic o_we
);
    logic [WIDTH_DEPTH-1:0] wptr, wptr_next;
    logic [WIDTH_DEPTH-1:0] wptr_inc;
    logic [WIDTH_DEPTH-1:0] rptr, rptr_next;
    logic [WIDTH_DEPTH-1:0] rptr_inc;

    logic empty, empty_next;
    logic full,  full_next;

    assign wptr_inc = wptr+1;
    assign rptr_inc = rptr+1;

    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            wptr  <= 0;
            rptr  <= 0;
            empty <= 1'b1;
            full  <= 1'b0;
        end
        else if (i_flush) begin
            wptr  <= 0;
            rptr  <= 0;
            empty <= 1'b1;
            full  <= 1'b0;
        end
        else begin
            wptr  <= wptr_next;
            rptr  <= rptr_next;
            empty <= empty_next;
            full  <= full_next;
        end
    end

    always_comb begin
        case({i_pop, i_push})
            2'b00: begin // No Pop, No Push
                wptr_next  = wptr;
                rptr_next  = rptr;
                empty_next = empty;
                full_next  = full;
                
                // Output
                o_we       = 1'b0;
            end
            2'b10: begin // Pop, No Push
                wptr_next = wptr;
                if (empty) begin
                    rptr_next  = rptr;
                    empty_next = 1'b1;
                    full_next  = 1'b0;
                end
                else begin
                    rptr_next  = rptr_inc;
                    empty_next = ( wptr == rptr_inc );
                    full_next  = 1'b0;
                end

                // Output
                o_we       = 1'b0;
            end
            2'b01: begin // No Pop, Push
                if (full) begin
                    wptr_next  = wptr;
                    empty_next = 1'b0;
                    full_next  = 1'b1;
                        
                    // Output
                    o_we       = 1'b0;
                end
                else begin
                    wptr_next  = wptr_inc;
                    empty_next = 1'b0;
                    full_next  = ( rptr == wptr_inc );
                        
                    // Output
                    o_we       = 1'b1;
                end
                rptr_next = rptr;
            end
            2'b11: begin // Pop, Push
                if (empty) begin
                    wptr_next  = wptr_inc;
                    rptr_next  = rptr;
                    empty_next = 1'b0;
                    full_next  = 1'b0;
                        
                    // Output
                    o_we       = 1'b1;
                end
                else if (full) begin
                    wptr_next  = wptr_inc;
                    rptr_next  = rptr_inc;
                    empty_next = 1'b0;
                    full_next  = 1'b1;
                        
                    // Output
                    o_we       = 1'b1;
                end
                else begin
                    wptr_next  = wptr_inc;
                    rptr_next  = rptr_inc;
                    empty_next = 1'b0;
                    full_next  = 1'b0;
                        
                    // Output
                    o_we       = 1'b1;
                end
            end
            default: begin
                wptr_next  = 0;
                rptr_next  = 0;
                empty_next = 1'b1;
                full_next  = 1'b0;

                // Output
                o_we       = 1'b0;
            end
        endcase
    end

    assign o_empty = empty;
    assign o_full  = full;

    assign o_push_addr = wptr;
    generate
        if (READ_DELAY == 0) begin
            assign o_pop_addr = rptr;
        end
        else if (READ_DELAY == 1) begin
            assign o_pop_addr = rptr_next;
        end
    endgenerate

endmodule

module fifo_regfile #(
    parameter  int DATA_WIDTH  = 32,
    parameter  int FIFO_DEPTH  = 32,

    localparam int WIDTH_DEPTH = $clog2(FIFO_DEPTH)
) (
    input  logic clk,
    input  logic reset_n,

    input  logic i_flush,

    input  logic                  i_push,
    input  logic [DATA_WIDTH-1:0] i_push_data,

    input  logic                  i_pop,
    output logic [DATA_WIDTH-1:0] o_pop_data,

    output logic                  o_empty,
    output logic                  o_full
);
    logic flush, push, pop, empty, full, we;
    logic [WIDTH_DEPTH-1:0] push_addr, pop_addr;
    logic [DATA_WIDTH-1:0]  push_data, pop_data;

    assign flush     = i_flush;
    assign push      = i_push;
    assign pop       = i_pop;

    assign push_data = i_push_data;

    fifo_control #(
        .FIFO_DEPTH  (FIFO_DEPTH),
        .READ_DELAY  (0)
    ) U_FIFO_CTRL (
        .clk         (clk),
        .reset_n     (reset_n),
        .i_flush     (flush),
        .i_push      (push),
        .i_pop       (pop),
        .o_empty     (empty),
        .o_full      (full),
        .o_push_addr (push_addr),
        .o_pop_addr  (pop_addr),
        .o_we        (we)
    );

    regfile #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ENTRIES       (FIFO_DEPTH),
        .READ_CHANNEL  (1),
        .WRITE_CHANNEL (1),
        .INITIAL_VALUE (0)
    ) U_FIFO_REGFILE (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (flush),
        .i_read_addr   (pop_addr),
        .o_read_data   (pop_data),
        .i_write_addr  (push_addr),
        .i_write_en    (we),
        .i_write_data  (push_data)
    );

    assign o_empty    = empty;
    assign o_full     = full;

    assign o_pop_data = pop_data;

endmodule

module fifo_bram #(
    parameter  int DATA_WIDTH  = 32,
    parameter  int FIFO_DEPTH  = 32,

    localparam int WIDTH_DEPTH = $clog2(FIFO_DEPTH)
) (
    input  logic clk,
    input  logic reset_n,

    input  logic i_flush,

    input  logic                  i_push,
    input  logic [DATA_WIDTH-1:0] i_push_data,

    input  logic                  i_pop,
    output logic [DATA_WIDTH-1:0] o_pop_data,

    output logic                  o_empty,
    output logic                  o_full
);
    logic flush, push, pop, empty, full, we;
    logic [WIDTH_DEPTH-1:0] push_addr, pop_addr;
    logic [DATA_WIDTH-1:0]  push_data, pop_data;

    logic                  push_empty_active; 
    logic [DATA_WIDTH-1:0] push_empty_buffer;

    assign flush     = i_flush;
    assign push      = i_push;
    assign pop       = i_pop;

    assign push_data = i_push_data;

    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            push_empty_active <= 1'b0;
            push_empty_buffer <= 0;
        end
        else if (i_flush) begin
            push_empty_active <= 1'b0;
            push_empty_buffer <= 0;
        end
        else begin
            if (push_empty_active) begin
                if (i_push & i_pop) begin
                    push_empty_active <= 1'b1;
                    push_empty_buffer <= i_push_data;
                end
                else begin
                    push_empty_active <= 1'b0;
                end
            end
            else begin
                if (o_empty & i_push) begin
                    push_empty_active <= 1'b1;
                    push_empty_buffer <= i_push_data;
                end
                else if ((push_addr == pop_addr) & i_push) begin
                    push_empty_active <= 1'b1;
                    push_empty_buffer <= i_push_data;
                end
            end
        end
    end

    fifo_control #(
        .FIFO_DEPTH  (FIFO_DEPTH),
        .READ_DELAY  (1)
    ) U_FIFO_CTRL (
        .clk         (clk),
        .reset_n     (reset_n),
        .i_flush     (flush),
        .i_push      (push),
        .i_pop       (pop),
        .o_empty     (empty),
        .o_full      (full),
        .o_push_addr (push_addr),
        .o_pop_addr  (pop_addr),
        .o_we        (we)
    );

    bram_custom #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ENTRIES       (FIFO_DEPTH)
    ) U_FIFO_BRAM (
        .clk           (clk),
        .i_read_addr   (pop_addr),
        .o_read_data   (pop_data),
        .i_write_addr  (push_addr),
        .i_write_en    (we),
        .i_write_data  (push_data)
    );

    assign o_empty    = empty;
    assign o_full     = full;

    assign o_pop_data = (push_empty_active)? push_empty_buffer : pop_data;

endmodule

module fifo_multichan_regfile #(
    parameter  int                    DATA_WIDTH    = 32,
    parameter  int                    ENTRIES       = 16,
    parameter  int                    READ_CHANNEL  = 2,
    parameter  int                    WRITE_CHANNEL = 2,
    parameter  int                    FIFO_ENTRY    = 32
) ();


endmodule
