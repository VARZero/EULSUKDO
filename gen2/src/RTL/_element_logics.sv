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

module fifo_multichan #(
    parameter  int                    DATA_WIDTH     = 32,
    parameter  int                    READ_CHANNEL   = 2,
    parameter  int                    WRITE_CHANNEL  = 2,
    parameter  int                    MIN_FIFO_ENTRY = 16,
    parameter  bit                    USE_BRAM       = 1'b0,

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
    //   use valid_gather
    // ============ LAYER 2: Ordering =========
    //   use FF
    // ============ LAYER 3: FIFO =============
    //   use fifo_regfile
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

    logic [PUSH_ORDERING_VG_LEN-1:0]   push_new_vg_valid;
    logic [PUSH_ORDERING_VG_WIDTH-1:0] push_new_vg_data;
    logic                              push_fifo_valid;
    logic [FIFO_DATA_WIDTH-1:0]        push_fifo_data;
    logic [OUT_ORDERING_VG_LEN-1:0]    out_new_vg_valid;
    logic [OUT_ORDERING_VG_WIDTH-1:0]  out_new_vg_data;
    logic                              pop_fifo_ready;
    logic [FIFO_DATA_WIDTH-1:0]        pop_fifo_data;

    logic output_room, bypass_to_output, drain_push_order;
    integer retained_count, source_position;

    // The output buffer accepts a complete FIFO word. If the FIFO is empty,
    // bypass its latency; otherwise its older data always has priority.
    assign output_room = !(|out_ord_vg_valid_reg[OUT_ORDERING_VG_LEN-1:FIFO_CHANNEL]);
    assign bypass_to_output = output_room && fifo_empty;
    assign pop_fifo_ready = reset_n && !i_flush && output_room && !fifo_empty;
    assign push_fifo_valid = reset_n && !i_flush && !bypass_to_output &&
        (&push_ord_vg_valid_reg[FIFO_CHANNEL-1:0]) && !fifo_full;
    assign push_fifo_data = push_ord_vg_data_reg[FIFO_DATA_WIDTH-1:0];
    assign drain_push_order = bypass_to_output || push_fifo_valid;

    // Reserve room for the whole next input bundle, including the current
    // input register. FIFO fullness alone cannot describe ordering-buffer space.
    // Ready is independent of i_push and i_pop (safe for Get-gated producers).
    assign o_push_ready = {WRITE_CHANNEL{reset_n && !i_flush &&
        (($countones(push_ord_vg_valid_reg) + $countones(push_valid_reg) -
          (drain_push_order ? $countones(push_ord_vg_valid_reg[FIFO_CHANNEL-1:0]) : 0))
            <= (PUSH_ORDERING_VG_LEN-WRITE_CHANNEL))}};
    assign o_pop_valid = out_ord_vg_valid_reg[READ_CHANNEL-1:0] &
        {READ_CHANNEL{reset_n && !i_flush}};
    assign o_pop_data = out_ord_vg_data_reg[READ_DATA_WIDTH-1:0];

    always_comb begin
        push_valid_reg_next = i_push & o_push_ready;
        push_data_reg_next  = i_push_data;
        push_new_vg_valid   = '0;
        push_new_vg_data    = '0;
        retained_count     = 0;
        source_position    = 0;

        // Compact retained data before appending the registered input. Keeping
        // only a fixed low slice would discard high entries when no drain occurs.
        for (int entry_idx = 0; entry_idx < PUSH_ORDERING_VG_LEN; entry_idx = entry_idx+1) begin
            source_position = entry_idx + (drain_push_order ? FIFO_CHANNEL : 0);
            if (source_position < PUSH_ORDERING_VG_LEN) begin
                if (push_ord_vg_valid_reg[source_position]) begin
                    push_new_vg_valid[retained_count] = 1'b1;
                    push_new_vg_data[retained_count*DATA_WIDTH +: DATA_WIDTH] =
                        push_ord_vg_data_reg[source_position*DATA_WIDTH +: DATA_WIDTH];
                    retained_count = retained_count+1;
                end
            end
        end
        for (int channel_idx = 0; channel_idx < WRITE_CHANNEL; channel_idx = channel_idx+1) begin
            if (push_valid_reg[channel_idx]) begin
                push_new_vg_valid[retained_count] = 1'b1;
                push_new_vg_data[retained_count*DATA_WIDTH +: DATA_WIDTH] =
                    push_data_reg[channel_idx*DATA_WIDTH +: DATA_WIDTH];
                retained_count = retained_count+1;
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

    valid_gather #(
        .DATA_WIDTH (DATA_WIDTH),
        .ENTRIES    (PUSH_ORDERING_VG_LEN)
    ) U_VG_PUSH (
        .i_valid (push_new_vg_valid),
        .i_data  (push_new_vg_data),
        .o_valid (push_ord_vg_valid_next),
        .o_data  (push_ord_vg_data_next)
    );

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

    valid_gather #(
        .DATA_WIDTH (DATA_WIDTH),
        .ENTRIES    (OUT_ORDERING_VG_LEN)
    ) U_VG_OUT (
        .i_valid (out_new_vg_valid),
        .i_data  (out_new_vg_data),
        .o_valid (out_ord_vg_valid_next),
        .o_data  (out_ord_vg_data_next)
    );


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
