`timescale 1ns/1ps

// Two FIFO ordering gate, with one memory instruction in flight at a time.
// Lower FIFO: tags admitted in program order (lane 0 is oldest).
// Upper FIFO: ready instructions, rotated until its head matches the lower head.
// Both heads remain allocated until the matching completion, NOT EX acceptance.
// A lower reservation also reserves an upper slot: both capacities are DEPTH.
module load_store_queue #(
    parameter int TAG_WIDTH = 35,
    parameter int INST_WIDTH = 92,
    parameter int ORDER_CHANNELS = 2,
    parameter int READY_CHANNELS = 1,
    parameter int DONE_CHANNELS = 5,
    parameter int DEPTH = 32,
    localparam int PTR_W = DEPTH > 1 ? $clog2(DEPTH) : 1,
    localparam int COUNT_W = $clog2(DEPTH+1),
    localparam int LANE_W = READY_CHANNELS > 1 ? $clog2(READY_CHANNELS) : 1,
    localparam int UPPER_W = INST_WIDTH+LANE_W,
    localparam int ORDER_BANKS = 1 << $clog2(ORDER_CHANNELS),
    localparam int ORDER_ROWS = (DEPTH+ORDER_BANKS-1)/ORDER_BANKS,
    localparam int ORDER_STORAGE = ORDER_ROWS*ORDER_BANKS,
    localparam int ORDER_PTR_W = ORDER_STORAGE > 1 ? $clog2(ORDER_STORAGE) : 1,
    localparam int ORDER_BANK_W = ORDER_BANKS > 1 ? $clog2(ORDER_BANKS) : 1,
    localparam int ORDER_ROW_W = ORDER_ROWS > 1 ? $clog2(ORDER_ROWS) : 1
) (
    input wire clk, reset_n,
    // Transfer pulses, not requests: producer must first observe o_order_ready.
    input wire [ORDER_CHANNELS-1:0] i_order_valid,
    input wire [ORDER_CHANNELS*TAG_WIDTH-1:0] i_order_tag,
    output wire o_order_ready,
    input wire [READY_CHANNELS-1:0] i_ready_valid,
    output logic [READY_CHANNELS-1:0] o_ready_get,
    input wire [READY_CHANNELS*INST_WIDTH-1:0] i_ready_data,
    output logic [READY_CHANNELS-1:0] o_ex_valid,
    input wire [READY_CHANNELS-1:0] i_ex_get,
    output logic [READY_CHANNELS*INST_WIDTH-1:0] o_ex_data,
    input wire [DONE_CHANNELS-1:0] i_done_valid,
    input wire [DONE_CHANNELS*TAG_WIDTH-1:0] i_done_tag
);
    logic [ORDER_PTR_W-1:0] order_read, order_write;
    logic [PTR_W-1:0] upper_read, upper_write;
    logic [COUNT_W-1:0] order_count, upper_count;
    logic in_flight;
    logic [LANE_W-1:0] arb_first;
    (* ram_style = "block" *) logic [UPPER_W-1:0] upper_memory [DEPTH];
    logic [TAG_WIDTH-1:0] order_forward_data;
    wire [TAG_WIDTH-1:0] order_bank_data [ORDER_BANKS];
    logic [ORDER_BANK_W-1:0] order_read_bank;
    wire [TAG_WIDTH-1:0] order_read_data = order_bank_data[order_read_bank];
    logic [UPPER_W-1:0] upper_read_data, upper_forward_data;
    logic order_forward_valid, upper_forward_valid;
    wire [TAG_WIDTH-1:0] order_head = order_forward_valid ? order_forward_data : order_read_data;
    wire [UPPER_W-1:0] upper_head = upper_forward_valid ? upper_forward_data : upper_read_data;
    wire [LANE_W-1:0] head_lane = upper_head[INST_WIDTH +: LANE_W];
    wire heads_valid = reset_n && order_count != 0 && upper_count != 0;
    wire heads_match = heads_valid && order_head == upper_head[0 +: TAG_WIDTH];
    wire issue_fire = |(o_ex_valid & i_ex_get);
    logic completion_match;
    wire finish = reset_n && (in_flight || issue_fire) && completion_match;
    logic ready_push, rotate, upper_push;
    logic [UPPER_W-1:0] upper_push_data;
    logic [LANE_W-1:0] selected_lane;
    logic [COUNT_W-1:0] order_push_count;
    logic [ORDER_PTR_W-1:0] order_push_addr [ORDER_CHANNELS];
    wire [ORDER_CHANNELS-1:0] order_push = i_order_valid & {ORDER_CHANNELS{o_order_ready}};

    function automatic logic [PTR_W-1:0] advance(input logic [PTR_W-1:0] ptr, input int amount);
        int next_addr;
        next_addr = int'(ptr)+amount;
        if (next_addr >= DEPTH) next_addr -= DEPTH;
        return PTR_W'(next_addr);
    endfunction

    function automatic logic [ORDER_PTR_W-1:0] order_advance(input logic [ORDER_PTR_W-1:0] ptr, input int amount);
        int next_addr;
        next_addr = int'(ptr)+amount;
        if (next_addr >= ORDER_STORAGE) next_addr -= ORDER_STORAGE;
        return ORDER_PTR_W'(next_addr);
    endfunction

    // NEL has a bundle handshake, and valid depends on get. Conservative room
    // for a full bundle avoids a valid->ready loop, including sparse bundles.
    assign o_order_ready = reset_n && int'(order_count) <= DEPTH-ORDER_CHANNELS;
    always_comb begin
        order_push_count = '0;
        for (int d = 0; d < ORDER_CHANNELS; d++) begin
            order_push_addr[d] = order_advance(order_write, int'(order_push_count));
            order_push_count += COUNT_W'(order_push[d]);
        end
    end

    // Serialize ready inputs, preserving the original execution lane in RAM.
    // Incoming instructions win the one RAM write port over recirculation.
    // Admissions are bounded by the lower FIFO, so they cannot starve rotation
    // forever; round-robin selection prevents starvation between ready lanes.
    always_comb begin
        int lane;
        o_ready_get = '0;
        selected_lane = '0;
        ready_push = 1'b0;
        lane = 0;
        for (int offset = 0; offset < READY_CHANNELS; offset++) begin
            lane = int'(arb_first)+offset;
            if (lane >= READY_CHANNELS) lane -= READY_CHANNELS;
            if (reset_n && int'(upper_count) < DEPTH && !ready_push && i_ready_valid[lane]) begin
                selected_lane = LANE_W'(lane);
                o_ready_get[lane] = 1'b1;
                ready_push = 1'b1;
            end
        end
        rotate = heads_valid && !heads_match && !in_flight && !ready_push;
        upper_push = ready_push || rotate;
        upper_push_data = upper_head;
        if (ready_push)
            upper_push_data = {selected_lane, i_ready_data[int'(selected_lane)*INST_WIDTH +: INST_WIDTH]};
    end

    always_comb begin
        o_ex_valid = '0;
        o_ex_data = '0;
        for (int e = 0; e < READY_CHANNELS; e++) begin
            if (head_lane == LANE_W'(e)) begin
                o_ex_valid[e] = heads_match && !in_flight;
                o_ex_data[e*INST_WIDTH +: INST_WIDTH] = upper_head[0 +: INST_WIDTH];
            end
        end
        completion_match = 1'b0;
        for (int d = 0; d < DONE_CHANNELS; d++)
            completion_match |= i_done_valid[d] && i_done_tag[d*TAG_WIDTH +: TAG_WIDTH] == order_head;
    end

    wire upper_pop = rotate || finish;
    wire [ORDER_PTR_W-1:0] order_read_next = order_advance(order_read, int'(finish));
    wire [PTR_W-1:0] upper_read_next = advance(upper_read, int'(upper_pop));
    // Consecutive tag writes land in distinct banks. Pad physical storage to a
    // bank multiple so this also holds at wraparound, but keep logical capacity
    // at DEPTH. Each bank has only one write port and can infer LUT RAM instead
    // of a DEPTH-wide register/mux network. This is still ONE ordered FIFO.
    for (genvar b = 0; b < ORDER_BANKS; b++) begin : G_ORDER_BANK
        (* ram_style = "distributed" *) logic [TAG_WIDTH-1:0] memory [ORDER_ROWS];
        logic write_enable;
        logic [ORDER_ROW_W-1:0] write_row;
        logic [TAG_WIDTH-1:0] write_data, read_data;
        always_comb begin
            write_enable = 1'b0; write_row = '0; write_data = '0;
            for (int d = 0; d < ORDER_CHANNELS; d++) begin
                if (order_push[d] && int'(order_push_addr[d]) % ORDER_BANKS == b) begin
                    write_enable = 1'b1;
                    write_row = ORDER_ROW_W'(int'(order_push_addr[d]) / ORDER_BANKS);
                    write_data = i_order_tag[d*TAG_WIDTH +: TAG_WIDTH];
                end
            end
        end
        always_ff @(posedge clk) begin
            if (write_enable) memory[write_row] <= write_data;
            read_data <= memory[ORDER_ROW_W'(int'(order_read_next) / ORDER_BANKS)];
        end
        assign order_bank_data[b] = read_data;
    end
    // Synchronous look-ahead reads plus explicit forwarding for empty->nonempty,
    // wraparound and a one-entry rotation. No RAM contents are reset.
    always_ff @(posedge clk) begin
        order_read_bank <= ORDER_BANK_W'(int'(order_read_next) % ORDER_BANKS);
        if (upper_push) upper_memory[upper_write] <= upper_push_data;
        upper_read_data <= upper_memory[upper_read_next];
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            order_read <= '0; order_write <= '0; order_count <= '0;
            upper_read <= '0; upper_write <= '0; upper_count <= '0;
            arb_first <= '0; in_flight <= 1'b0;
            order_forward_valid <= 1'b0; upper_forward_valid <= 1'b0;
            order_forward_data <= '0; upper_forward_data <= '0;
        end else begin
            order_read <= order_read_next;
            order_write <= order_advance(order_write, int'(order_push_count));
            order_count <= order_count + order_push_count - COUNT_W'(finish);
            upper_read <= upper_read_next;
            upper_write <= advance(upper_write, int'(upper_push));
            upper_count <= upper_count + COUNT_W'(ready_push) - COUNT_W'(finish);
            if (ready_push)
                arb_first <= int'(selected_lane) == READY_CHANNELS-1 ? '0 : selected_lane+1'b1;
            if (finish) in_flight <= 1'b0;
            else if (issue_fire) in_flight <= 1'b1;
            order_forward_valid <= 1'b0;
            for (int d = 0; d < ORDER_CHANNELS; d++) begin
                if (order_push[d] && order_push_addr[d] == order_read_next) begin
                    order_forward_valid <= 1'b1;
                    order_forward_data <= i_order_tag[d*TAG_WIDTH +: TAG_WIDTH];
                end
            end
            upper_forward_valid <= upper_push && upper_write == upper_read_next;
            if (upper_push && upper_write == upper_read_next) upper_forward_data <= upper_push_data;
        end
    end

    initial begin
        if (DEPTH < ORDER_CHANNELS || ORDER_CHANNELS < 1 || READY_CHANNELS < 1 || DONE_CHANNELS < 1)
            $fatal(1, "LSQ needs DEPTH >= ORDER_CHANNELS and positive channel counts");
        if (TAG_WIDTH < 1 || INST_WIDTH < TAG_WIDTH) $fatal(1, "Invalid LSQ payload width");
    end
    // synthesis translate_off
    always @(posedge clk) if (reset_n) begin
        assert (!(|i_order_valid) || o_order_ready) else $fatal(1, "LSQ order overflow");
        assert (upper_count <= order_count && int'(order_count) <= DEPTH) else $fatal(1, "LSQ reservation violated");
        assert (!in_flight || heads_match) else $fatal(1, "LSQ lost in-flight heads");
        assert ($onehot0(o_ex_valid)) else $fatal(1, "Multiple LSQ issues");
    end
    // synthesis translate_on
endmodule
