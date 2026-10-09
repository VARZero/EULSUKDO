`timescale 1ns/1ps
module flow_control_logic #(
    // Instruction Set Parameters
    parameter int IS_INST_PC_BITWIDTH                   = 32,
    parameter int IS_INST_PC_STEP                       = 4,
    parameter int IS_INST_BITWIDTH                      = 32,
    parameter int IS_INST_REGS                          = 32,
    parameter int IS_INST_OPERANDS                      = 2,
    parameter int IS_INST_IMM                           = 32,

    // Execution Unit Parameters
    parameter int EX_INST_MICROOP_BITWIDTH              = 5,

    // EULSUKDO Structure Parameters
    parameter int STRUCT_DECODE_NEW_INST                = 2,
    parameter int STRUCT_INST_STATE_ENTRIES             = 128,
    parameter int STRUCT_PHYREGS                        = 64,
    parameter int STRUCT_EX_PATH                        = 3,
    parameter int STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]   = {1, 3, 1},
    parameter int STRUCT_EX_CORES                       = 5,
    parameter int STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES] = {1, 1, 1, 1, 1},
    parameter int STRUCT_EX_OUT_RESULT_SUM              = 5,
    parameter int STRUCT_EX_BRANCH                      = 1,
    parameter int STRUCT_PRM_ENTRY_UPDATE               = 5,
    parameter int STRUCT_PRM_ENTRY_BUFFER               = 4,
    parameter int STRUCT_UNALLOCATE_PHYREG              = 4,
    parameter int STRUCT_FLOW_WINDOWS                   = 8,
    parameter int STRUCT_FLOW_PC_MAX_RANGE              = 16,

    // Synthesis Create Local Parameters
    localparam int _BITWIDTH_IS_INST_REGS               = $clog2(IS_INST_REGS),
    localparam int _BITWIDTH_STRUCT_INST_STATE_ENTRIES  = $clog2(STRUCT_INST_STATE_ENTRIES),
    localparam int _BITWIDTH_STRUCT_PHYREGS             = $clog2(STRUCT_PHYREGS),
    localparam int _BITWIDTH_STRUCT_EX_PATH             = $clog2(STRUCT_EX_PATH),
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = (STRUCT_FLOW_WINDOWS > 1)? $clog2(STRUCT_FLOW_WINDOWS) : 1,
    localparam int _BITWIDTH_READY_PRM                  = _BITWIDTH_STRUCT_INST_STATE_ENTRIES+_BITWIDTH_STRUCT_PHYREGS,
    localparam int _BITWIDTH_FLOW_WINDOWS_PC            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH,
    localparam int _BITWIDTH_INTERNAL_INST_WIDTH        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS) // rs1..n
                                                         + IS_INST_OPERANDS, // Ready1..n
    localparam int _BITWIDTH_EX_INST_WIDTH              = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_EX_PATH
                                                         + EX_INST_MICROOP_BITWIDTH
                                                         + IS_INST_IMM
                                                         + _BITWIDTH_STRUCT_PHYREGS // rd
                                                         + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS), // rs1..n
    localparam int _BITWIDTH_EX_RESULT_WIDTH            = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // rd
    localparam int _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG  = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
                                                         + _BITWIDTH_STRUCT_PHYREGS, // Retired Register
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Flag
                                                         + 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
) (
    input  wire                                                                        clk,
    input  wire                                                                        reset_n,
        
    // NEL input-response accounting. IM responses must remain in program order.
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_nel_recv_valid,
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_nel_recv_keep,
    input wire i_nel_recv_control,
    output wire o_nel_discard,
    // All renamed instructions, including no-RD and x0 instructions.
    input wire [STRUCT_DECODE_NEW_INST-1:0] i_nel_new_inst_valid,
    input wire [STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_nel_new_inst_pc,
    // Resolved branch/jump-register result: {next_pc, flow, instruction_pc}.
    // EX supplies the actual next PC for both taken and not-taken branches.
    input wire [STRUCT_EX_BRANCH-1:0] i_wbc_branch_valid,
    input wire [STRUCT_EX_BRANCH*(IS_INST_PC_BITWIDTH+_BITWIDTH_FLOW_WINDOWS_PC)-1:0] i_wbc_branch_data,

    // Done PC Input (WBC)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                         i_wbc_done_pc_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0]       i_wbc_done_pc_data,
        
    // Jump/Branch Information Input (NEL)
    input  wire                                                                        i_nel_jumpbranch_valid,
    input  wire [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                                i_nel_jumpbranch_data,

    input wire [_BITWIDTH_FLOW_WINDOWS_PC-1:0] i_nel_jumpbranch_pc,

    // Retired Physical Registers Input (NEL)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_nel_retired_phyreg_valid,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0] i_nel_retired_phyreg_data,

    // Request New Instruction Output (IM)
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                           o_im_req_pc_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_im_req_pc_get,
    output wire [(STRUCT_DECODE_NEW_INST *_BITWIDTH_FLOW_WINDOWS_PC)-1:0]                 o_im_req_pc,

    // Unallocate Retired Registers Output (PRM)
    output wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                         o_prm_unallocate_phyreg_valid,
    output wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]          o_prm_unallocate_phyreg_data
);

    localparam int FLOW_W = _BITWIDTH_STRUCT_FLOW_WINDOWS;
    localparam int PC_W = IS_INST_PC_BITWIDTH;
    localparam int TAG_W = _BITWIDTH_FLOW_WINDOWS_PC;
    localparam int BATCH_W = (STRUCT_DECODE_NEW_INST > 1)? $clog2(STRUCT_DECODE_NEW_INST+1) : 1;
    localparam int USED_W = (STRUCT_FLOW_PC_MAX_RANGE > 1)? $clog2(STRUCT_FLOW_PC_MAX_RANGE+1) : 1;
    localparam int BRANCH_W = PC_W+TAG_W;

    logic [FLOW_W-1:0] head, head_next, tail, tail_next;
    logic current_valid, current_valid_next;
    logic [FLOW_W-1:0] current_flow, current_flow_next;
    logic [USED_W-1:0] current_used, current_used_next;
    logic [PC_W-1:0] next_pc, next_pc_next;

    // One fetch bundle in flight: no instruction beyond an unresolved control
    // can be renamed. Request lanes handshake independently and hold their PCs.
    logic batch_active, batch_active_next, batch_discard, batch_discard_next;
    logic batch_control, batch_control_next;
    logic [STRUCT_DECODE_NEW_INST-1:0] request_pending, request_pending_next;
    logic [PC_W-1:0] batch_pc, batch_pc_next;
    logic [FLOW_W-1:0] batch_flow, batch_flow_next;
    logic [BATCH_W-1:0] batch_size, batch_size_next;
    logic [BATCH_W-1:0] received, received_next, kept, kept_next, renamed, renamed_next;
    logic branch_pending, branch_pending_next;
    logic [TAG_W-1:0] branch_tag, branch_tag_next;

    logic [STRUCT_FLOW_WINDOWS-1:0] fdu_open, fdu_close;
    wire [STRUCT_FLOW_WINDOWS-1:0] fdu_active, fdu_release;
    wire [STRUCT_UNALLOCATE_PHYREG-1:0] fdu_retire_valid [0:STRUCT_FLOW_WINDOWS-1];
    wire [STRUCT_UNALLOCATE_PHYREG*_BITWIDTH_STRUCT_PHYREGS-1:0] fdu_retire_data [0:STRUCT_FLOW_WINDOWS-1];
    integer recv_sum, keep_sum, rename_sum, used_sum, request_size;
    integer lane, result_lane;
    logic result_found;

    assign o_im_req_pc_valid = request_pending & {STRUCT_DECODE_NEW_INST{reset_n}};
    assign o_nel_discard = batch_discard && reset_n;
    assign o_prm_unallocate_phyreg_valid = fdu_retire_valid[head];
    assign o_prm_unallocate_phyreg_data = fdu_retire_data[head];

    genvar request_lane, window_idx;
    generate
        for (request_lane = 0; request_lane < STRUCT_DECODE_NEW_INST; request_lane = request_lane+1) begin : G_REQUEST
            assign o_im_req_pc[request_lane*TAG_W +: TAG_W] =
                {batch_flow, (batch_pc + PC_W'(request_lane*IS_INST_PC_STEP))};
        end
        for (window_idx = 0; window_idx < STRUCT_FLOW_WINDOWS; window_idx = window_idx+1) begin : G_WINDOW
            flow_detect_unit #(
                .WINDOW_ID(window_idx), .FLOW_W(FLOW_W), .PC_W(PC_W),
                .PC_STEP(IS_INST_PC_STEP), .MAX_INSTRUCTIONS(STRUCT_FLOW_PC_MAX_RANGE),
                .DECODE(STRUCT_DECODE_NEW_INST), .DONE_CHANNELS(STRUCT_EX_OUT_RESULT_SUM),
                .RETURNS(STRUCT_UNALLOCATE_PHYREG), .PHY_W(_BITWIDTH_STRUCT_PHYREGS)
            ) U_FDU (
                .clk(clk), .reset_n(reset_n), .i_open(fdu_open[window_idx]), .i_start_pc(next_pc),
                .i_close(fdu_close[window_idx]), .o_active(fdu_active[window_idx]),
                .i_new_valid(i_nel_new_inst_valid), .i_new_pc(i_nel_new_inst_pc),
                .i_done_valid(i_wbc_done_pc_valid), .i_done_pc(i_wbc_done_pc_data),
                .i_retired_valid(i_nel_retired_phyreg_valid), .i_retired_data(i_nel_retired_phyreg_data),
                .i_retire_enable(reset_n && (head == FLOW_W'(window_idx))),
                .o_retired_valid(fdu_retire_valid[window_idx]), .o_retired_data(fdu_retire_data[window_idx]),
                .o_release(fdu_release[window_idx])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            head <= '0; tail <= '0; current_valid <= 0; current_flow <= '0; current_used <= '0;
            next_pc <= '0; batch_active <= 0; batch_discard <= 0; batch_control <= 0;
            request_pending <= '0; batch_pc <= '0; batch_flow <= '0; batch_size <= '0;
            received <= '0; kept <= '0; renamed <= '0; branch_pending <= 0; branch_tag <= '0;
        end
        else begin
            head <= head_next; tail <= tail_next;
            current_valid <= current_valid_next; current_flow <= current_flow_next; current_used <= current_used_next;
            next_pc <= next_pc_next; batch_active <= batch_active_next;
            batch_discard <= batch_discard_next; batch_control <= batch_control_next;
            request_pending <= request_pending_next; batch_pc <= batch_pc_next; batch_flow <= batch_flow_next;
            batch_size <= batch_size_next; received <= received_next; kept <= kept_next; renamed <= renamed_next;
            branch_pending <= branch_pending_next; branch_tag <= branch_tag_next;
`ifndef SYNTHESIS
            if (batch_active && ((recv_sum > int'(batch_size)) || (rename_sum > keep_sum)))
                $error("FCL response/rename accounting violated the single in-order fetch-bundle contract");
            if (used_sum > STRUCT_FLOW_PC_MAX_RANGE) $error("FCL window capacity exceeded");
`endif
        end
    end

    always_comb begin
        head_next = head; tail_next = tail;
        current_valid_next = current_valid; current_flow_next = current_flow; current_used_next = current_used;
        next_pc_next = next_pc;
        batch_active_next = batch_active; batch_discard_next = batch_discard; batch_control_next = batch_control;
        request_pending_next = request_pending & ~i_im_req_pc_get;
        batch_pc_next = batch_pc; batch_flow_next = batch_flow; batch_size_next = batch_size;
        received_next = received; kept_next = kept; renamed_next = renamed;
        branch_pending_next = branch_pending; branch_tag_next = branch_tag;
        fdu_open = '0; fdu_close = '0;
        recv_sum = int'(received); keep_sum = int'(kept); rename_sum = int'(renamed);
        used_sum = int'(current_used); request_size = 0; result_found = 0;

        if (reset_n) begin
            // Circular IDs are allocated and released in creation order. A newer
            // completed window cannot release a register still read by an older one.
            if (fdu_release[head]) head_next = (int'(head) == STRUCT_FLOW_WINDOWS-1)? '0 : head+1'b1;
            if (!current_valid && !batch_active && !branch_pending && !fdu_active[tail]) begin
                fdu_open[tail] = 1'b1;
                current_valid_next = 1'b1; current_flow_next = tail; current_used_next = '0;
                tail_next = (int'(tail) == STRUCT_FLOW_WINDOWS-1)? '0 : tail+1'b1;
            end
            if (current_valid && !batch_active && !branch_pending) begin
                request_size = STRUCT_FLOW_PC_MAX_RANGE-int'(current_used);
                if (request_size > STRUCT_DECODE_NEW_INST) request_size = STRUCT_DECODE_NEW_INST;
                batch_active_next = 1'b1; batch_discard_next = 0; batch_control_next = 0;
                batch_pc_next = next_pc; batch_flow_next = current_flow;
                batch_size_next = BATCH_W'(request_size);
                received_next = '0; kept_next = '0; renamed_next = '0;
                next_pc_next = next_pc + PC_W'(request_size*IS_INST_PC_STEP);
                for (lane = 0; lane < STRUCT_DECODE_NEW_INST; lane = lane+1)
                    request_pending_next[lane] = (lane < request_size);
            end

            if (batch_active) begin
                for (lane = 0; lane < STRUCT_DECODE_NEW_INST; lane = lane+1) begin
                    if (i_nel_recv_valid[lane]) recv_sum = recv_sum+1;
                    if (i_nel_recv_keep[lane]) keep_sum = keep_sum+1;
                    if (i_nel_new_inst_valid[lane]) begin rename_sum = rename_sum+1; used_sum = used_sum+1; end
                end
                received_next = BATCH_W'(recv_sum); kept_next = BATCH_W'(keep_sum); renamed_next = BATCH_W'(rename_sum);
                current_used_next = USED_W'(used_sum);
                if (i_nel_recv_control) batch_discard_next = 1'b1;

                if (i_nel_jumpbranch_valid) begin
                    batch_control_next = 1'b1;
                    branch_tag_next = i_nel_jumpbranch_pc;
                    if (i_nel_jumpbranch_data[1] || i_nel_jumpbranch_data[2]) branch_pending_next = 1'b1;
                    else next_pc_next = i_nel_jumpbranch_data[3 +: PC_W];
                end
                // Wait for all requested responses, including discarded suffixes,
                // and for every retained instruction to actually commit its rename.
                if (!(|request_pending_next) && (recv_sum == int'(batch_size)) && (rename_sum == keep_sum)) begin
                    batch_active_next = 1'b0; batch_discard_next = 1'b0;
                    if (batch_control_next || (used_sum == STRUCT_FLOW_PC_MAX_RANGE)) begin
                        fdu_close[current_flow] = 1'b1; current_valid_next = 1'b0;
                    end
                end
            end
            // Match the instruction identity, not just a branch-result lane.
            // The result may arrive while a discarded IM suffix is still draining.
            for (result_lane = 0; result_lane < STRUCT_EX_BRANCH; result_lane = result_lane+1) begin
                if (!result_found && branch_pending_next && i_wbc_branch_valid[result_lane] &&
                    (i_wbc_branch_data[result_lane*BRANCH_W +: TAG_W] == branch_tag_next)) begin
                    result_found = 1'b1; branch_pending_next = 1'b0;
                    next_pc_next = i_wbc_branch_data[result_lane*BRANCH_W+TAG_W +: PC_W];
                end
            end
        end
    end
endmodule

// A window retains retired register numbers until it is closed, all admitted
// instructions complete, and the FCL grants this oldest window the return port.
module flow_detect_unit #(
    parameter int WINDOW_ID = 0,
    parameter int FLOW_W = 3,
    parameter int PC_W = 32,
    parameter int PC_STEP = 4,
    parameter int MAX_INSTRUCTIONS = 16,
    parameter int DECODE = 2,
    parameter int DONE_CHANNELS = 5,
    parameter int RETURNS = 4,
    parameter int PHY_W = 6,
    localparam int TAG_W = FLOW_W+PC_W,
    localparam int RETIRED_W = PHY_W+TAG_W,
    localparam int COUNT_W = (MAX_INSTRUCTIONS > 1)? $clog2(MAX_INSTRUCTIONS+1) : 1
) (
    input logic clk, reset_n,
    input logic i_open, i_close,
    input logic [PC_W-1:0] i_start_pc,
    output logic o_active,
    input logic [DECODE-1:0] i_new_valid,
    input logic [DECODE*TAG_W-1:0] i_new_pc,
    input logic [DONE_CHANNELS-1:0] i_done_valid,
    input logic [DONE_CHANNELS*TAG_W-1:0] i_done_pc,
    input logic [DECODE-1:0] i_retired_valid,
    input logic [DECODE*RETIRED_W-1:0] i_retired_data,
    input logic i_retire_enable,
    output wire [RETURNS-1:0] o_retired_valid,
    output wire [RETURNS*PHY_W-1:0] o_retired_data,
    output wire o_release
);
    logic active, active_next, closed, closed_next;
    logic [PC_W-1:0] start_pc, start_pc_next;
    logic [MAX_INSTRUCTIONS-1:0] admitted, admitted_next, done_bits, done_bits_next;
    logic [COUNT_W-1:0] retired_count, retired_count_next;
    logic [DECODE-1:0] fifo_push;
    logic [DECODE*PHY_W-1:0] fifo_push_data;
    wire [DECODE-1:0] fifo_ready;
    wire [RETURNS-1:0] fifo_valid;
    wire [RETURNS*PHY_W-1:0] fifo_data;
    logic [PC_W-1:0] delta_pc;
    integer lane, slot, count_next;
    wire completed = active && closed && (admitted == done_bits);

    assign o_active = active;
    assign o_retired_valid = fifo_valid & {RETURNS{reset_n && i_retire_enable && completed}};
    assign o_retired_data = fifo_data;
    assign o_release = reset_n && i_retire_enable && completed && (retired_count == 0);

    fifo_multichan #(
        .DATA_WIDTH(PHY_W), .READ_CHANNEL(RETURNS), .WRITE_CHANNEL(DECODE),
        .MIN_FIFO_ENTRY(MAX_INSTRUCTIONS), .USE_BRAM(1'b0)
    ) U_RETIRED_REGISTERS (
        .clk(clk), .reset_n(reset_n), .i_flush(i_open),
        .i_push(fifo_push), .i_push_data(fifo_push_data), .o_push_ready(fifo_ready),
        .i_pop(o_retired_valid), .o_pop_valid(fifo_valid), .o_pop_data(fifo_data)
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active <= 0; closed <= 0; start_pc <= '0;
            admitted <= '0; done_bits <= '0; retired_count <= '0;
        end
        else begin
            active <= active_next; closed <= closed_next; start_pc <= start_pc_next;
            admitted <= admitted_next; done_bits <= done_bits_next; retired_count <= retired_count_next;
`ifndef SYNTHESIS
            if (|(fifo_push & ~fifo_ready)) $error("FDU retirement FIFO overflow");
            if (count_next > MAX_INSTRUCTIONS) $error("FDU retirement capacity exceeded");
`endif
        end
    end

    always_comb begin
        active_next = active; closed_next = closed; start_pc_next = start_pc;
        admitted_next = admitted; done_bits_next = done_bits;
        fifo_push = '0; fifo_push_data = '0;
        delta_pc = '0; slot = 0;
        count_next = int'(retired_count)-$countones(o_retired_valid);
        if (reset_n && active && !i_open) begin
            for (lane = 0; lane < DECODE; lane = lane+1) begin
                delta_pc = i_new_pc[lane*TAG_W +: PC_W]-start_pc;
                if (!closed && i_new_valid[lane] && (i_new_pc[lane*TAG_W+PC_W +: FLOW_W] == FLOW_W'(WINDOW_ID)) &&
                    (delta_pc < PC_W'(MAX_INSTRUCTIONS*PC_STEP)) && ((delta_pc % PC_STEP) == 0)) begin
                    slot = int'(delta_pc/PC_STEP); admitted_next[slot] = 1'b1;
                end
                delta_pc = i_retired_data[lane*RETIRED_W +: PC_W]-start_pc;
                if (!closed && i_retired_valid[lane] &&
                    (i_retired_data[lane*RETIRED_W+PC_W +: FLOW_W] == FLOW_W'(WINDOW_ID)) &&
                    (delta_pc < PC_W'(MAX_INSTRUCTIONS*PC_STEP)) && ((delta_pc % PC_STEP) == 0) &&
                    (i_retired_data[lane*RETIRED_W+TAG_W +: PHY_W] != 0)) begin
                    fifo_push[lane] = 1'b1;
                    fifo_push_data[lane*PHY_W +: PHY_W] = i_retired_data[lane*RETIRED_W+TAG_W +: PHY_W];
                    count_next = count_next+1;
                end
            end
            for (lane = 0; lane < DONE_CHANNELS; lane = lane+1) begin
                delta_pc = i_done_pc[lane*TAG_W +: PC_W]-start_pc;
                if (i_done_valid[lane] && (i_done_pc[lane*TAG_W+PC_W +: FLOW_W] == FLOW_W'(WINDOW_ID)) &&
                    (delta_pc < PC_W'(MAX_INSTRUCTIONS*PC_STEP)) && ((delta_pc % PC_STEP) == 0)) begin
                    slot = int'(delta_pc/PC_STEP);
                    if (admitted_next[slot]) done_bits_next[slot] = 1'b1;
                end
            end
            if (i_close) closed_next = 1'b1;
            if (o_release) active_next = 1'b0;
        end
        if (reset_n && i_open) begin
            active_next = 1'b1; closed_next = 1'b0; start_pc_next = i_start_pc;
            admitted_next = '0; done_bits_next = '0; count_next = 0;
        end
        retired_count_next = COUNT_W'(count_next);
    end
endmodule
