`timescale 1ns/1ps

module regfile #(
    parameter  int                    DATA_WIDTH    = 32,
    parameter  int                    ENTRIES       = 16,
    parameter  int                    READ_CHANNEL  = 2,
    parameter  int                    WRITE_CHANNEL = 2,
    parameter  logic [DATA_WIDTH-1:0] INITIAL_VALUE = 0,

    localparam int ADDR_ENTRY       = (ENTRIES > 1)? $clog2(ENTRIES) : 1,

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

    localparam int ADDR_ENTRY       = (ENTRIES > 1)? $clog2(ENTRIES) : 1,

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
            if (demux_pos == int'(i_sel)) begin
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

    localparam int WIDTH_DEPTH = (FIFO_DEPTH > 1)? $clog2(FIFO_DEPTH) : 1
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

    assign wptr_inc = (wptr == WIDTH_DEPTH'(FIFO_DEPTH-1))? '0 : wptr+1'b1;
    assign rptr_inc = (rptr == WIDTH_DEPTH'(FIFO_DEPTH-1))? '0 : rptr+1'b1;

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
                    full_next  = (FIFO_DEPTH == 1);
                        
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

    localparam int WIDTH_DEPTH = (FIFO_DEPTH > 1)? $clog2(FIFO_DEPTH) : 1
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

    localparam int WIDTH_DEPTH = (FIFO_DEPTH > 1)? $clog2(FIFO_DEPTH) : 1
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
            // Forward only an accepted write that collides with the BRAM's
            // look-ahead read address. A rejected write while full must never
            // replace the visible head, and the next read removes the bypass.
            push_empty_active <= we && (push_addr == pop_addr);
            if (we && (push_addr == pop_addr)) push_empty_buffer <= push_data;
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

// This is deliberately NOT an arbitrary-mask gather. The FIFO supplies two
// halves: the lower half can have holes only in its first READ_CHANNEL lanes;
// its remaining tail and the upper half are each packed valid prefixes.
// The upper half is either retained output data or a newly fetched FIFO word.
module fifo_output_gather #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_CHANNEL = 7,
    parameter int READ_CHANNEL = 3,
    localparam int WORD_WIDTH = FIFO_CHANNEL*DATA_WIDTH,
    localparam int COUNT_WIDTH = $clog2(FIFO_CHANNEL+1),
    localparam int HEAD_COUNT_WIDTH = $clog2(READ_CHANNEL+1)
) (
    input  logic [2*FIFO_CHANNEL-1:0] i_valid,
    input  logic [2*WORD_WIDTH-1:0] i_data,
    output logic [2*FIFO_CHANNEL-1:0] o_valid,
    output logic [2*WORD_WIDTH-1:0] o_data
);
    logic [READ_CHANNEL-1:0] head_valid;
    logic [READ_CHANNEL*DATA_WIDTH-1:0] head_data;
    logic [HEAD_COUNT_WIDTH-1:0] head_count, head_holes;
    logic [COUNT_WIDTH-1:0] low_count;
    logic [FIFO_CHANNEL-1:0] tail_valid;
    logic [WORD_WIDTH-1:0] tail_data, upper_data;
    logic [FIFO_CHANNEL-1:0] tail_valid_shift [0:HEAD_COUNT_WIDTH];
    logic [WORD_WIDTH-1:0] tail_data_shift [0:HEAD_COUNT_WIDTH];
    logic [2*FIFO_CHANNEL-1:0] upper_valid_shift [0:COUNT_WIDTH];
    logic [2*WORD_WIDTH-1:0] upper_data_shift [0:COUNT_WIDTH];

    // Sparse output Get is allowed: e.g. popping B from A,B,C keeps A,C.
    // Only this small head needs arbitrary stable compaction.
    generate
        if (READ_CHANNEL == 1) begin : G_SINGLE_HEAD
            assign head_valid = i_valid[0];
            assign head_data = i_data[DATA_WIDTH-1:0] & {DATA_WIDTH{i_valid[0]}};
        end
        else begin : G_MULTI_HEAD
            valid_gather #(
                .DATA_WIDTH (DATA_WIDTH),
                .ENTRIES (READ_CHANNEL)
            ) U_HEAD_GATHER (
                .i_valid (i_valid[READ_CHANNEL-1:0]),
                .i_data (i_data[READ_CHANNEL*DATA_WIDTH-1:0]),
                .o_valid (head_valid),
                .o_data (head_data)
            );
        end
    endgenerate

    always_comb begin
        head_count = '0;
        low_count = '0;
        tail_valid = '0;
        tail_data = '0;
        upper_data = '0;
        for (int lane = 0; lane < READ_CHANNEL; lane = lane+1)
            head_count = head_count + HEAD_COUNT_WIDTH'(i_valid[lane]);
        head_holes = HEAD_COUNT_WIDTH'(READ_CHANNEL) - head_count;

        for (int lane = 0; lane < FIFO_CHANNEL; lane = lane+1) begin
            low_count = low_count + COUNT_WIDTH'(i_valid[lane]);
            upper_data[lane*DATA_WIDTH +: DATA_WIDTH] =
                i_data[(FIFO_CHANNEL+lane)*DATA_WIDTH +: DATA_WIDTH] &
                {DATA_WIDTH{i_valid[FIFO_CHANNEL+lane]}};
            if (lane >= READ_CHANNEL) begin
                tail_valid[lane] = i_valid[lane];
                tail_data[lane*DATA_WIDTH +: DATA_WIDTH] =
                    i_data[lane*DATA_WIDTH +: DATA_WIDTH] & {DATA_WIDTH{i_valid[lane]}};
            end
        end

        // The intact tail closes at most READ_CHANNEL holes. Append the
        // packed upper word at low_count; no full-buffer crossbar or new FFs.
        // Constant word-sized shift stages avoid a bit-level barrel shifter
        // driven by count*DATA_WIDTH (instruction widths need not be powers of 2).
        tail_valid_shift[0] = tail_valid;
        tail_data_shift[0] = tail_data;
        for (int stage = 0; stage < HEAD_COUNT_WIDTH; stage = stage+1) begin
            tail_valid_shift[stage+1] = head_holes[stage] ?
                (tail_valid_shift[stage] >> (1 << stage)) : tail_valid_shift[stage];
            tail_data_shift[stage+1] = head_holes[stage] ?
                (tail_data_shift[stage] >> ((1 << stage)*DATA_WIDTH)) : tail_data_shift[stage];
        end
        upper_valid_shift[0] = {{FIFO_CHANNEL{1'b0}}, i_valid[2*FIFO_CHANNEL-1:FIFO_CHANNEL]};
        upper_data_shift[0] = {{WORD_WIDTH{1'b0}}, upper_data};
        for (int stage = 0; stage < COUNT_WIDTH; stage = stage+1) begin
            upper_valid_shift[stage+1] = low_count[stage] ?
                (upper_valid_shift[stage] << (1 << stage)) : upper_valid_shift[stage];
            upper_data_shift[stage+1] = low_count[stage] ?
                (upper_data_shift[stage] << ((1 << stage)*DATA_WIDTH)) : upper_data_shift[stage];
        end
        o_valid = upper_valid_shift[COUNT_WIDTH];
        o_data = upper_data_shift[COUNT_WIDTH];
        o_valid[FIFO_CHANNEL-1:0] = o_valid[FIFO_CHANNEL-1:0] |
            tail_valid_shift[HEAD_COUNT_WIDTH] | FIFO_CHANNEL'(head_valid);
        o_data[WORD_WIDTH-1:0] = o_data[WORD_WIDTH-1:0] |
            tail_data_shift[HEAD_COUNT_WIDTH] | WORD_WIDTH'(head_data);
    end
endmodule

// Stable compaction tree: compact each half independently, then shift the
// right half by the left count. Payload selection is local to each merge.
module fifo_input_compact #(
    parameter int DATA_WIDTH = 32,
    parameter int CHANNELS = 7,
    localparam int COUNT_WIDTH = $clog2(CHANNELS+1)
) (
    input  logic [CHANNELS-1:0] i_valid,
    input  logic [CHANNELS*DATA_WIDTH-1:0] i_data,
    output logic [COUNT_WIDTH-1:0] o_count,
    output logic [CHANNELS*DATA_WIDTH-1:0] o_data
);
    generate
        if (CHANNELS == 1) begin : G_LEAF
            assign o_count = i_valid;
            assign o_data = i_data & {DATA_WIDTH{i_valid[0]}};
        end
        else begin : G_MERGE
            localparam int LEFT = CHANNELS/2;
            localparam int RIGHT = CHANNELS-LEFT;
            localparam int LEFT_COUNT_WIDTH = $clog2(LEFT+1);
            localparam int RIGHT_COUNT_WIDTH = $clog2(RIGHT+1);
            logic [LEFT_COUNT_WIDTH-1:0] left_count;
            logic [RIGHT_COUNT_WIDTH-1:0] right_count;
            logic [LEFT*DATA_WIDTH-1:0] left_data;
            logic [RIGHT*DATA_WIDTH-1:0] right_data;
            logic [CHANNELS*DATA_WIDTH-1:0] right_shift [0:LEFT_COUNT_WIDTH];
            fifo_input_compact #(.DATA_WIDTH(DATA_WIDTH), .CHANNELS(LEFT)) U_LEFT (
                .i_valid(i_valid[LEFT-1:0]), .i_data(i_data[LEFT*DATA_WIDTH-1:0]),
                .o_count(left_count), .o_data(left_data)
            );
            fifo_input_compact #(.DATA_WIDTH(DATA_WIDTH), .CHANNELS(RIGHT)) U_RIGHT (
                .i_valid(i_valid[CHANNELS-1:LEFT]), .i_data(i_data[CHANNELS*DATA_WIDTH-1:LEFT*DATA_WIDTH]),
                .o_count(right_count), .o_data(right_data)
            );
            always_comb begin
                o_count = COUNT_WIDTH'(left_count) + COUNT_WIDTH'(right_count);
                right_shift[0] = (CHANNELS*DATA_WIDTH)'(right_data);
                for (int stage = 0; stage < LEFT_COUNT_WIDTH; stage = stage+1)
                    right_shift[stage+1] = left_count[stage] ?
                        (right_shift[stage] << ((1 << stage)*DATA_WIDTH)) : right_shift[stage];
                o_data = (CHANNELS*DATA_WIDTH)'(left_data) | right_shift[LEFT_COUNT_WIDTH];
            end
        end
    endgenerate
endmodule

// Append a sparse input bundle to an already packed prefix. Only new input
// lanes need arbitrary compaction; their packed result moves as one word.
module fifo_input_append #(
    parameter int DATA_WIDTH = 32,
    parameter int INPUT_CHANNEL = 7,
    parameter int BUFFER_ENTRIES = 14,
    localparam int BUFFER_WIDTH = BUFFER_ENTRIES*DATA_WIDTH,
    localparam int COUNT_WIDTH = $clog2(BUFFER_ENTRIES+1)
) (
    input  logic [BUFFER_ENTRIES-1:0] i_retained_valid,
    input  logic [BUFFER_WIDTH-1:0] i_retained_data,
    input  logic [COUNT_WIDTH-1:0] i_retained_count,
    input  logic [INPUT_CHANNEL-1:0] i_valid,
    input  logic [INPUT_CHANNEL*DATA_WIDTH-1:0] i_data,
    output logic [BUFFER_ENTRIES-1:0] o_valid,
    output logic [BUFFER_WIDTH-1:0] o_data
);
    logic [INPUT_CHANNEL-1:0] packed_valid;
    logic [INPUT_CHANNEL*DATA_WIDTH-1:0] packed_data;
    logic [$clog2(INPUT_CHANNEL+1)-1:0] packed_count;
    logic [BUFFER_ENTRIES-1:0] shifted_valid [0:COUNT_WIDTH];
    logic [BUFFER_WIDTH-1:0] shifted_data [0:COUNT_WIDTH];

    fifo_input_compact #(.DATA_WIDTH(DATA_WIDTH), .CHANNELS(INPUT_CHANNEL)) U_INPUT_COMPACT (
        .i_valid(i_valid), .i_data(i_data), .o_count(packed_count), .o_data(packed_data)
    );

    always_comb begin
        for (int lane = 0; lane < INPUT_CHANNEL; lane = lane+1)
            packed_valid[lane] = (lane < int'(packed_count));
        shifted_valid[0] = BUFFER_ENTRIES'(packed_valid);
        shifted_data[0] = BUFFER_WIDTH'(packed_data);
        for (int stage = 0; stage < COUNT_WIDTH; stage = stage+1) begin
            shifted_valid[stage+1] = i_retained_count[stage] ?
                (shifted_valid[stage] << (1 << stage)) : shifted_valid[stage];
            shifted_data[stage+1] = i_retained_count[stage] ?
                (shifted_data[stage] << ((1 << stage)*DATA_WIDTH)) : shifted_data[stage];
        end
        o_valid = i_retained_valid | shifted_valid[COUNT_WIDTH];
        o_data = shifted_data[COUNT_WIDTH];
        for (int lane = 0; lane < BUFFER_ENTRIES; lane = lane+1)
            o_data[lane*DATA_WIDTH +: DATA_WIDTH] = o_data[lane*DATA_WIDTH +: DATA_WIDTH] |
                (i_retained_data[lane*DATA_WIDTH +: DATA_WIDTH] & {DATA_WIDTH{i_retained_valid[lane]}});
    end
endmodule

module fifo_multichan #(
    parameter  int                    DATA_WIDTH     = 32,
    parameter  int                    READ_CHANNEL   = 2,
    parameter  int                    WRITE_CHANNEL  = 2,
    parameter  int                    MIN_FIFO_ENTRY = 16,
    parameter  bit                    USE_BRAM       = 1'b0,
    // Preserve the original gather as an A/B reference; all clients default
    // to the packed-output implementation. Sparse external push/pop is valid.
    parameter  bit                    OPTIMIZED_OUTPUT_GATHER = 1'b1,
    parameter  bit                    OPTIMIZED_INPUT_GATHER = 1'b0,

    localparam int READ_DATA_WIDTH  = DATA_WIDTH * READ_CHANNEL,
    localparam int WRITE_DATA_WIDTH = DATA_WIDTH * WRITE_CHANNEL
) (
    input  logic clk,
    input  logic reset_n,

    input  logic i_flush,

    input  logic [WRITE_CHANNEL-1:0]    i_push,
    output logic [WRITE_CHANNEL-1:0]    o_push_ready,
    input  logic [WRITE_DATA_WIDTH-1:0] i_push_data,

    input  logic [READ_CHANNEL-1:0]     i_pop,
    output logic [READ_CHANNEL-1:0]     o_pop_valid,
    output logic [READ_DATA_WIDTH-1:0]  o_pop_data
);
    //   input: FF
    // ============ LAYER 1: Input ============
    //   compact sparse lanes in lane order
    // ============ LAYER 2: Ordering =========
    //   use FF
    // ============ LAYER 3: FIFO =============
    //   use fifo_regfile or fifo_bram
    // ============ LAYER 4: Output Buffering =
    //   use FF
    // ============ LAYER 5: Output ===========

    localparam int FIFO_CHANNEL           = (READ_CHANNEL > WRITE_CHANNEL)?
                                             READ_CHANNEL : WRITE_CHANNEL;
    localparam int FIFO_DATA_WIDTH        = FIFO_CHANNEL * DATA_WIDTH;
    localparam int FIFO_DEPTH_IN          = MIN_FIFO_ENTRY/FIFO_CHANNEL
                                            + ( ( (MIN_FIFO_ENTRY%FIFO_CHANNEL) > 0 )? 1 : 0 );

    localparam int PUSH_ORDERING_VG_LEN   = (FIFO_CHANNEL == WRITE_CHANNEL)?
                                            FIFO_CHANNEL*2 : FIFO_CHANNEL+WRITE_CHANNEL;
    localparam int PUSH_ORDERING_VG_WIDTH = PUSH_ORDERING_VG_LEN * DATA_WIDTH;

    localparam int OUT_ORDERING_VG_LEN    = FIFO_CHANNEL*2;
    localparam int OUT_ORDERING_VG_WIDTH  = OUT_ORDERING_VG_LEN * DATA_WIDTH;
    

    logic [WRITE_CHANNEL-1:0]          push_valid_reg, push_valid_reg_next;
    logic [WRITE_DATA_WIDTH-1:0]       push_data_reg, push_data_reg_next;

    logic [PUSH_ORDERING_VG_LEN-1:0]   push_ord_vg_valid_reg, push_ord_vg_valid_next;
    logic [PUSH_ORDERING_VG_WIDTH-1:0] push_ord_vg_data_reg, push_ord_vg_data_next;

    logic [OUT_ORDERING_VG_LEN-1:0]    out_ord_vg_valid_reg, out_ord_vg_valid_next;
    logic [OUT_ORDERING_VG_WIDTH-1:0]  out_ord_vg_data_reg, out_ord_vg_data_next;

    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            push_valid_reg        <= 0;
            push_data_reg         <= 0;
            
            push_ord_vg_valid_reg <= 0;
            push_ord_vg_data_reg  <= 0;

            out_ord_vg_valid_reg  <= 0;
            out_ord_vg_data_reg   <= 0;
        end
        else if (i_flush) begin
            push_valid_reg        <= 0;
            push_data_reg         <= 0;
            
            push_ord_vg_valid_reg <= 0;
            push_ord_vg_data_reg  <= 0;

            out_ord_vg_valid_reg  <= 0;
            out_ord_vg_data_reg   <= 0;
        end
        else begin
            push_valid_reg        <= push_valid_reg_next;
            push_data_reg         <= push_data_reg_next;
            
            push_ord_vg_valid_reg <= push_ord_vg_valid_next;
            push_ord_vg_data_reg  <= push_ord_vg_data_next;

            out_ord_vg_valid_reg  <= out_ord_vg_valid_next;
            out_ord_vg_data_reg   <= out_ord_vg_data_next;
        end
    end
    
    logic                              fifo_empty, fifo_full;

    logic                              push_fifo_valid;
    logic [FIFO_DATA_WIDTH-1:0]        push_fifo_data;
    logic [OUT_ORDERING_VG_LEN-1:0]    out_new_vg_valid;
    logic [OUT_ORDERING_VG_WIDTH-1:0]  out_new_vg_data;
    logic                              pop_fifo_ready;
    logic [FIFO_DATA_WIDTH-1:0]        pop_fifo_data;

    logic output_room, bypass_to_output, drain_push_order;
    localparam int PUSH_COUNT_WIDTH = $clog2(PUSH_ORDERING_VG_LEN+WRITE_CHANNEL+1);
    wire [PUSH_ORDERING_VG_LEN-1:0] retained_valid;
    wire [PUSH_ORDERING_VG_WIDTH-1:0] retained_data;
    wire [PUSH_COUNT_WIDTH-1:0] retained_count, push_occupancy;
    logic [PUSH_COUNT_WIDTH-1:0] append_position [0:WRITE_CHANNEL];
    logic [PUSH_ORDERING_VG_LEN-1:0] compact_append_valid;
    logic [PUSH_ORDERING_VG_WIDTH-1:0] compact_append_data;

    generate
        if (OPTIMIZED_INPUT_GATHER) begin : G_PACKED_INPUT
            fifo_input_append #(
                .DATA_WIDTH (DATA_WIDTH),
                .INPUT_CHANNEL (WRITE_CHANNEL),
                .BUFFER_ENTRIES (PUSH_ORDERING_VG_LEN)
            ) U_APPEND (
                .i_retained_valid (retained_valid), .i_retained_data (retained_data),
                .i_retained_count ($clog2(PUSH_ORDERING_VG_LEN+1)'(retained_count)),
                .i_valid (push_valid_reg), .i_data (push_data_reg),
                .o_valid (compact_append_valid), .o_data (compact_append_data)
            );
        end
        else begin : G_DIRECT_INPUT
            assign compact_append_valid = '0;
            assign compact_append_data = '0;
        end
    endgenerate

    // The output buffer accepts a complete FIFO word. If the FIFO is empty,
    // bypass its latency; otherwise its older data always has priority.
    assign output_room = !(|out_ord_vg_valid_reg[OUT_ORDERING_VG_LEN-1:FIFO_CHANNEL]);
    assign bypass_to_output = output_room && fifo_empty;
    assign pop_fifo_ready = reset_n && !i_flush && output_room && !fifo_empty;
    assign push_fifo_valid = reset_n && !i_flush && !bypass_to_output &&
        (&push_ord_vg_valid_reg[FIFO_CHANNEL-1:0]) && !fifo_full;
    assign push_fifo_data = push_ord_vg_data_reg[FIFO_DATA_WIDTH-1:0];
    assign drain_push_order = bypass_to_output || push_fifo_valid;

    // Ordering state is already a packed prefix. Draining removes one fixed
    // FIFO word, so retaining it needs only a constant shift, not a gather.
    assign retained_valid = drain_push_order ? (push_ord_vg_valid_reg >> FIFO_CHANNEL) : push_ord_vg_valid_reg;
    assign retained_data = drain_push_order ? (push_ord_vg_data_reg >> FIFO_DATA_WIDTH) : push_ord_vg_data_reg;
    assign retained_count = PUSH_COUNT_WIDTH'($countones(retained_valid));
    assign push_occupancy = retained_count + PUSH_COUNT_WIDTH'($countones(push_valid_reg));

    // Reserve room for the whole next input bundle, including the current
    // input register. FIFO fullness alone cannot describe ordering-buffer space.
    // Ready is independent of i_push and i_pop (safe for Get-gated producers).
    assign o_push_ready = {WRITE_CHANNEL{reset_n && !i_flush &&
        (push_occupancy <= PUSH_COUNT_WIDTH'(PUSH_ORDERING_VG_LEN-WRITE_CHANNEL))}};
    assign o_pop_valid = out_ord_vg_valid_reg[READ_CHANNEL-1:0] &
        {READ_CHANNEL{reset_n && !i_flush}};
    assign o_pop_data = out_ord_vg_data_reg[READ_DATA_WIDTH-1:0];

    always_comb begin
        push_valid_reg_next = i_push & o_push_ready;
        push_data_reg_next  = i_push_data;
        append_position[0] = retained_count;
        for (int channel_idx = 0; channel_idx < WRITE_CHANNEL; channel_idx = channel_idx+1) begin
            append_position[channel_idx+1] = append_position[channel_idx] + PUSH_COUNT_WIDTH'(push_valid_reg[channel_idx]);
        end

        if (OPTIMIZED_INPUT_GATHER) begin
            push_ord_vg_valid_next = compact_append_valid;
            push_ord_vg_data_next = compact_append_data;
        end
        else begin
        // Decode bounded entry positions into fixed data slices. This avoids
        // serial variable-position writes across a wide packed vector. Incoming
        // lanes append in order, so the next state is packed without U_VG_PUSH.
        push_ord_vg_valid_next = retained_valid;
        push_ord_vg_data_next = '0;
        for (int entry_idx = 0; entry_idx < PUSH_ORDERING_VG_LEN; entry_idx = entry_idx+1) begin
            push_ord_vg_data_next[entry_idx*DATA_WIDTH +: DATA_WIDTH] =
                retained_data[entry_idx*DATA_WIDTH +: DATA_WIDTH] & {DATA_WIDTH{retained_valid[entry_idx]}};
            for (int channel_idx = 0; channel_idx < WRITE_CHANNEL; channel_idx = channel_idx+1) begin
                if (push_valid_reg[channel_idx] && (append_position[channel_idx] == PUSH_COUNT_WIDTH'(entry_idx))) begin
                    push_ord_vg_valid_next[entry_idx] = 1'b1;
                    push_ord_vg_data_next[entry_idx*DATA_WIDTH +: DATA_WIDTH] =
                        push_ord_vg_data_next[entry_idx*DATA_WIDTH +: DATA_WIDTH] |
                        push_data_reg[channel_idx*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end

        end

        out_new_vg_valid = out_ord_vg_valid_reg;
        out_new_vg_data  = out_ord_vg_data_reg;
        out_new_vg_valid[READ_CHANNEL-1:0] =
            out_ord_vg_valid_reg[READ_CHANNEL-1:0] & ~i_pop;
        if (pop_fifo_ready) begin
            out_new_vg_valid[OUT_ORDERING_VG_LEN-1:FIFO_CHANNEL] = '1;
            out_new_vg_data[OUT_ORDERING_VG_WIDTH-1:FIFO_DATA_WIDTH] = pop_fifo_data;
        end
        else if (bypass_to_output) begin
            out_new_vg_valid[OUT_ORDERING_VG_LEN-1:FIFO_CHANNEL] = push_ord_vg_valid_reg[FIFO_CHANNEL-1:0];
            out_new_vg_data[OUT_ORDERING_VG_WIDTH-1:FIFO_DATA_WIDTH] = push_ord_vg_data_reg[FIFO_DATA_WIDTH-1:0];
        end
    end

    generate
        if (USE_BRAM == 1'b0) begin
            fifo_regfile #(
                .DATA_WIDTH (FIFO_DATA_WIDTH),
                .FIFO_DEPTH (FIFO_DEPTH_IN)
            ) U_FIFO_RF (
                .clk         (clk),
                .reset_n     (reset_n),
                .i_flush     (i_flush),
                .i_push      (push_fifo_valid),
                .i_push_data (push_fifo_data),
                .i_pop       (pop_fifo_ready),
                .o_pop_data  (pop_fifo_data),
                .o_empty     (fifo_empty),
                .o_full      (fifo_full)
            );
        end
        else begin
            fifo_bram #(
                .DATA_WIDTH (FIFO_DATA_WIDTH),
                .FIFO_DEPTH (FIFO_DEPTH_IN)
            ) U_FIFO_BRAM (
                .clk         (clk),
                .reset_n     (reset_n),
                .i_flush     (i_flush),
                .i_push      (push_fifo_valid),
                .i_push_data (push_fifo_data),
                .i_pop       (pop_fifo_ready),
                .o_pop_data  (pop_fifo_data),
                .o_empty     (fifo_empty),
                .o_full      (fifo_full)
            );
        end
    endgenerate

    generate
        if (OPTIMIZED_OUTPUT_GATHER) begin : G_PACKED_OUTPUT
            fifo_output_gather #(
                .DATA_WIDTH (DATA_WIDTH),
                .FIFO_CHANNEL (FIFO_CHANNEL),
                .READ_CHANNEL (READ_CHANNEL)
            ) U_GATHER (
                .i_valid (out_new_vg_valid),
                .i_data  (out_new_vg_data),
                .o_valid (out_ord_vg_valid_next),
                .o_data  (out_ord_vg_data_next)
            );
        end
        else begin : G_GENERIC_OUTPUT
            valid_gather #(
                .DATA_WIDTH (DATA_WIDTH),
                .ENTRIES    (OUT_ORDERING_VG_LEN)
            ) U_VG_OUT (
                .i_valid (out_new_vg_valid),
                .i_data  (out_new_vg_data),
                .o_valid (out_ord_vg_valid_next),
                .o_data  (out_ord_vg_data_next)
            );
        end
    endgenerate


endmodule

module allocator #(
    parameter  int                    ENTRIES            = 16,
    parameter  int                    START_VALUE        = 0,
    parameter  int                    ALLOCATE_CHANNEL   = 2,
    parameter  int                    UNALLOCATE_CHANNEL = 2,
    parameter  bit                    USE_BRAM           = 1'b0,

    localparam int                    ENTRIES_WIDTH      = (START_VALUE+ENTRIES > 1)? $clog2(START_VALUE+ENTRIES) : 1,
    localparam int                    ALLOCATE_WIDTH     = ENTRIES_WIDTH * ALLOCATE_CHANNEL,
    localparam int                    UNALLOCATE_WIDTH   = ENTRIES_WIDTH * UNALLOCATE_CHANNEL
) (
    input  logic clk,
    input  logic reset_n,

    input  logic i_flush,

    input  logic [UNALLOCATE_CHANNEL-1:0] i_unallocate,
    output logic [UNALLOCATE_CHANNEL-1:0] o_unallocate_ready,
    input  logic [UNALLOCATE_WIDTH-1:0]   i_unallocate_data,

    input  logic [ALLOCATE_CHANNEL-1:0]   i_allocate,
    output logic [ALLOCATE_CHANNEL-1:0]   o_allocate_valid,
    output logic [ALLOCATE_WIDTH-1:0]     o_allocate_data
);
    localparam int INIT_COUNT_WIDTH = (ENTRIES > 1)? $clog2(ENTRIES+1) : 1;

    typedef enum logic [1:0] {
        IDLE_S, SETTING_S, ALLOCATING_S
    } state_s;

    state_s state, state_next;
    logic [INIT_COUNT_WIDTH-1:0] init_count, init_count_next;
    logic fifo_flush;
    logic [UNALLOCATE_CHANNEL-1:0] fifo_push, fifo_push_ready;
    logic [UNALLOCATE_WIDTH-1:0] fifo_push_data;
    logic [ALLOCATE_CHANNEL-1:0] fifo_pop, fifo_pop_valid;
    logic [ALLOCATE_WIDTH-1:0] fifo_pop_data;
    integer init_channel, init_remaining;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state      <= IDLE_S;
            init_count <= '0;
        end
        else begin
            state      <= state_next;
            init_count <= init_count_next;
        end
    end

    // Offers depend on FIFO state, never on the consumer's Get.
    assign o_allocate_valid = fifo_pop_valid &
        {ALLOCATE_CHANNEL{reset_n && !i_flush && (state == ALLOCATING_S)}};
    assign o_allocate_data = fifo_pop_data;
    assign o_unallocate_ready = fifo_push_ready &
        {UNALLOCATE_CHANNEL{reset_n && !i_flush && (state == ALLOCATING_S)}};

    always_comb begin
        state_next      = state;
        init_count_next = init_count;
        fifo_flush      = i_flush || (state == IDLE_S);
        fifo_push       = '0;
        fifo_push_data  = '0;
        fifo_pop        = '0;
        init_remaining  = ENTRIES-int'(init_count);

        case (state)
            IDLE_S: begin
                init_count_next = '0;
                state_next      = SETTING_S;
            end
            SETTING_S: begin
                // Retry the same initialization bundle until the FIFO accepts it.
                // Count entries (not encoded IDs) so offsets, partial tails, and
                // ENTRIES smaller than UNALLOCATE_CHANNEL are all well-defined.
                for (init_channel = 0; init_channel < UNALLOCATE_CHANNEL; init_channel = init_channel+1) begin
                    fifo_push_data[init_channel*ENTRIES_WIDTH +: ENTRIES_WIDTH] =
                        ENTRIES_WIDTH'(START_VALUE+int'(init_count)+init_channel);
                    fifo_push[init_channel] = (init_channel < init_remaining) && (&fifo_push_ready);
                end
                if (&fifo_push_ready) begin
                    if (init_remaining <= UNALLOCATE_CHANNEL) begin
                        init_count_next = INIT_COUNT_WIDTH'(ENTRIES);
                        state_next      = ALLOCATING_S;
                    end
                    else init_count_next = init_count + INIT_COUNT_WIDTH'(UNALLOCATE_CHANNEL);
                end
            end
            ALLOCATING_S: begin
                fifo_push      = i_unallocate & o_unallocate_ready;
                fifo_push_data = i_unallocate_data;
                fifo_pop       = i_allocate & o_allocate_valid;
            end
            default: state_next = IDLE_S;
        endcase

        if (!reset_n || i_flush) begin
            state_next      = IDLE_S;
            init_count_next = '0;
            fifo_flush      = 1'b1;
            fifo_push       = '0;
            fifo_pop        = '0;
        end
    end

    fifo_multichan #(
        .DATA_WIDTH     (ENTRIES_WIDTH),
        .READ_CHANNEL   (ALLOCATE_CHANNEL),
        .WRITE_CHANNEL  (UNALLOCATE_CHANNEL),
        .MIN_FIFO_ENTRY (ENTRIES),
        .USE_BRAM       (USE_BRAM)
    ) U_ALLOC_FIFO (
        .clk            (clk),
        .reset_n        (reset_n),
        .i_flush        (fifo_flush),
        .i_push         (fifo_push),
        .o_push_ready   (fifo_push_ready),
        .i_push_data    (fifo_push_data),
        .i_pop          (fifo_pop),
        .o_pop_valid    (fifo_pop_valid),
        .o_pop_data     (fifo_pop_data)
    );

endmodule
