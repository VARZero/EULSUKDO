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
    localparam int _BITWIDTH_STRUCT_FLOW_WINDOWS        = $clog2(STRUCT_FLOW_WINDOWS),
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
        
    // Done PC Input (WBC)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                         i_wbc_done_pc_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_EX_DONE_PC) )-1:0]       i_wbc_done_pc_data,
    input  wire [STRUCT_EX_BRANCH-1:0]                                                i_wbc_branch_valid,
    input  wire [(STRUCT_EX_BRANCH*(_BITWIDTH_STRUCT_JUMP_BRANCH_INFO))-1:0]          i_wbc_branch_data,
        
    // Jump/Branch Information Input (NEL)
    input  wire                                                                        i_nel_jumpbranch_valid,
    input  wire [_BITWIDTH_STRUCT_JUMP_BRANCH_INFO-1:0]                                i_nel_jumpbranch_data,

    // Retired Physical Registers Input (NEL)
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_nel_retired_phyreg_valid,
    input  wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG) )-1:0] i_nel_retired_phyreg_data,

    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_im_recv_inst_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_im_recv_inst_get,
    input  wire [(STRUCT_DECODE_NEW_INST*_BITWIDTH_FLOW_WINDOWS_PC)-1:0]               i_im_recv_pc,
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                          o_im_recv_discard,

    // Request New Instruction Output (IM)
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                          o_im_req_pc_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_im_req_pc_get,
    output logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_FLOW_WINDOWS_PC) )-1:0]          o_im_req_pc,

    // Unallocate Retired Registers Output (PRM)
    output logic [STRUCT_UNALLOCATE_PHYREG-1:0]                                        o_prm_unallocate_phyreg_valid,
    output logic [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]         o_prm_unallocate_phyreg_data
);
    localparam int RETIRE_DEPTH = STRUCT_PHYREGS+STRUCT_DECODE_NEW_INST;

    logic [IS_INST_PC_BITWIDTH-1:0] next_pc, next_pc_next;
    logic [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] flow_id, flow_id_next, redirect_flow;
    logic [STRUCT_FLOW_WINDOWS-1:0] flow_active, flow_active_next;
    logic [STRUCT_FLOW_WINDOWS-1:0] flow_closed, flow_closed_next;
    logic [STRUCT_FLOW_WINDOWS-1:0] flow_discard, flow_discard_next;
    logic [31:0] flow_pending [0:STRUCT_FLOW_WINDOWS-1];
    logic [31:0] flow_pending_next [0:STRUCT_FLOW_WINDOWS-1];
    logic [31:0] flow_requested, flow_requested_next;
    logic [31:0] flow_inflight [0:STRUCT_FLOW_WINDOWS-1];
    logic [31:0] flow_inflight_next [0:STRUCT_FLOW_WINDOWS-1];
    logic [31:0] flow_order [0:STRUCT_FLOW_WINDOWS-1];
    logic [31:0] flow_order_next [0:STRUCT_FLOW_WINDOWS-1];
    logic [31:0] next_order, next_order_next;
    logic flow_wait, flow_wait_next;
    logic redirect_pending, redirect_pending_next, redirect_found;
    logic [IS_INST_PC_BITWIDTH-1:0] redirect_pc, redirect_pc_next;

    logic [RETIRE_DEPTH-1:0] retire_valid, retire_valid_next;
    logic [_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG-1:0] retire_data [0:RETIRE_DEPTH-1];
    logic [_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG-1:0] retire_data_next [0:RETIRE_DEPTH-1];
    logic [STRUCT_FLOW_WINDOWS-1:0] retire_remain;
    integer flow_idx, lane, index, out_lane, free_index, target_flow;
    logic older_active;

    always_comb begin
        next_pc_next = next_pc;
        flow_id_next = flow_id;
        flow_wait_next = flow_wait;
        redirect_pending_next = redirect_pending;
        redirect_pc_next = redirect_pc;
        redirect_flow = flow_id;
        redirect_found = 1'b0;
        next_order_next = next_order;
        flow_active_next = flow_active;
        flow_closed_next = flow_closed;
        flow_discard_next = flow_discard;
        flow_requested_next = flow_requested;
        for (flow_idx = 0; flow_idx < STRUCT_FLOW_WINDOWS; flow_idx++) begin
            flow_inflight_next[flow_idx] = flow_inflight[flow_idx];
            flow_pending_next[flow_idx] = flow_pending[flow_idx];
            flow_order_next[flow_idx] = flow_order[flow_idx];
        end

        o_im_req_pc_valid = '0;
        o_im_req_pc = '0;
        for (lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
            o_im_req_pc[lane*_BITWIDTH_FLOW_WINDOWS_PC +: _BITWIDTH_FLOW_WINDOWS_PC] =
                {flow_id, next_pc_next};
            if (!flow_wait && !redirect_pending && !i_nel_jumpbranch_valid &&
                !(|i_wbc_branch_valid) && flow_requested_next < STRUCT_FLOW_PC_MAX_RANGE) begin
                if (lane == 0) o_im_req_pc_valid[lane] = 1'b1;
                else if (o_im_req_pc_valid[lane-1] && i_im_req_pc_get[lane-1])
                    o_im_req_pc_valid[lane] = 1'b1;
            end
            if (i_im_req_pc_get[lane] && o_im_req_pc_valid[lane]) begin
                next_pc_next = next_pc_next + IS_INST_PC_BITWIDTH'(IS_INST_PC_STEP);
                flow_requested_next++;
                flow_pending_next[flow_id]++;
            end
        end
        for (lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
            target_flow = int'(i_im_recv_pc[lane*_BITWIDTH_FLOW_WINDOWS_PC + IS_INST_PC_BITWIDTH +: _BITWIDTH_STRUCT_FLOW_WINDOWS]);
            if (i_im_recv_inst_valid[lane] && target_flow < STRUCT_FLOW_WINDOWS) begin
                if (i_im_recv_inst_get[lane] && flow_pending_next[target_flow] != 0) begin
                    flow_pending_next[target_flow]--;
                    if (!flow_discard[target_flow]) flow_inflight_next[target_flow]++;
                end
            end
        end

        // Count IM-to-NEL acceptance, including an instruction held in NEL
        // Stage 1, so its flow cannot be reused before rename completes.
        for (lane = 0; lane < STRUCT_EX_OUT_RESULT_SUM; lane++) begin
            target_flow = int'(i_wbc_done_pc_data[lane*_BITWIDTH_STRUCT_EX_DONE_PC + IS_INST_PC_BITWIDTH +: _BITWIDTH_STRUCT_FLOW_WINDOWS]);
            if (i_wbc_done_pc_valid[lane] && target_flow < STRUCT_FLOW_WINDOWS && flow_inflight_next[target_flow] != 0)
                flow_inflight_next[target_flow]--;
        end

        if (i_nel_jumpbranch_valid) begin
            flow_closed_next[flow_id] = 1'b1;
            flow_discard_next[flow_id] = 1'b1;
            if (i_nel_jumpbranch_data[IS_INST_PC_BITWIDTH] ||
                i_nel_jumpbranch_data[IS_INST_PC_BITWIDTH+1]) begin
                flow_wait_next = 1'b1;
            end
            else begin
                redirect_pending_next = 1'b1;
                redirect_pc_next = i_nel_jumpbranch_data[0 +: IS_INST_PC_BITWIDTH];
            end
        end
        if (|i_wbc_branch_valid) begin
            redirect_pending_next = 1'b1;
            redirect_pc_next = i_wbc_branch_data[0 +: IS_INST_PC_BITWIDTH];
            flow_wait_next = 1'b0;
        end
        if (flow_requested_next >= STRUCT_FLOW_PC_MAX_RANGE && !i_nel_jumpbranch_valid &&
            !flow_wait && !redirect_pending && !(|i_wbc_branch_valid)) begin
            flow_closed_next[flow_id] = 1'b1;
            redirect_pending_next = 1'b1;
            redirect_pc_next = next_pc_next;
        end

        // The oldest active flow retires first. A replacement register is
        // returned only after every instruction in that flow has completed.
        retire_valid_next = '0;
        retire_remain = '0;
        o_prm_unallocate_phyreg_valid = '0;
        o_prm_unallocate_phyreg_data = '0;
        out_lane = 0;
        free_index = 0;
        older_active = 1'b0;
        target_flow = 0;
        for (index = 0; index < RETIRE_DEPTH; index++) begin
            retire_data_next[index] = '0;
        end
        for (index = 0; index < RETIRE_DEPTH; index++) begin
            if (retire_valid[index]) begin
                target_flow = int'(retire_data[index][IS_INST_PC_BITWIDTH +: _BITWIDTH_STRUCT_FLOW_WINDOWS]);
                older_active = 1'b0;
                for (flow_idx = 0; flow_idx < STRUCT_FLOW_WINDOWS; flow_idx++) begin
                    if (flow_active_next[flow_idx] && flow_order[flow_idx] < flow_order[target_flow])
                        older_active = 1'b1;
                end
                if (flow_closed_next[target_flow] && flow_inflight_next[target_flow] == 0 &&
                    flow_pending_next[target_flow] == 0 &&
                    !older_active && out_lane < STRUCT_UNALLOCATE_PHYREG) begin
                    o_prm_unallocate_phyreg_valid[out_lane] = 1'b1;
                    o_prm_unallocate_phyreg_data[out_lane*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS] =
                        retire_data[index][IS_INST_PC_BITWIDTH+_BITWIDTH_STRUCT_FLOW_WINDOWS +: _BITWIDTH_STRUCT_PHYREGS];
                    out_lane++;
                end
                else begin
                    retire_valid_next[free_index] = 1'b1;
                    retire_data_next[free_index] = retire_data[index];
                    retire_remain[target_flow] = 1'b1;
                    free_index++;
                end
            end
        end
        for (lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
            if (i_nel_retired_phyreg_valid[lane] && free_index < RETIRE_DEPTH) begin
                retire_valid_next[free_index] = 1'b1;
                retire_data_next[free_index] =
                    i_nel_retired_phyreg_data[lane*_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG +: _BITWIDTH_STRUCT_RETIRED_PHYREG_MSG];
                target_flow = int'(i_nel_retired_phyreg_data[lane*_BITWIDTH_STRUCT_RETIRED_PHYREG_MSG + IS_INST_PC_BITWIDTH +: _BITWIDTH_STRUCT_FLOW_WINDOWS]);
                if (target_flow < STRUCT_FLOW_WINDOWS) retire_remain[target_flow] = 1'b1;
                free_index++;
            end
        end

        for (flow_idx = 0; flow_idx < STRUCT_FLOW_WINDOWS; flow_idx++) begin
            if (flow_closed_next[flow_idx] && flow_inflight_next[flow_idx] == 0 &&
                flow_pending_next[flow_idx] == 0 &&
                !retire_remain[flow_idx]) begin
                flow_active_next[flow_idx] = 1'b0;
                flow_closed_next[flow_idx] = 1'b0;
                flow_discard_next[flow_idx] = 1'b0;
            end
        end

        // Do not reuse a window until its instructions and retired-register
        // records have drained. A redirect waits when every window is active.
        for (flow_idx = 0; flow_idx < STRUCT_FLOW_WINDOWS; flow_idx++) begin
            if (!redirect_found && !flow_active_next[flow_idx] && flow_idx != int'(flow_id)) begin
                redirect_flow = _BITWIDTH_STRUCT_FLOW_WINDOWS'(flow_idx);
                redirect_found = 1'b1;
            end
        end
        if (redirect_pending_next && redirect_found) begin
            flow_id_next = redirect_flow;
            next_pc_next = redirect_pc_next;
            redirect_pending_next = 1'b0;
            flow_active_next[redirect_flow] = 1'b1;
            flow_closed_next[redirect_flow] = 1'b0;
            flow_order_next[redirect_flow] = next_order;
            next_order_next = next_order+1'b1;
            flow_inflight_next[redirect_flow] = 0;
            flow_pending_next[redirect_flow] = 0;
            flow_discard_next[redirect_flow] = 1'b0;
            flow_requested_next = 0;
        end
    end

    for (genvar dlane = 0; dlane < STRUCT_DECODE_NEW_INST; dlane++) begin : GEN_DISCARD
        wire [_BITWIDTH_STRUCT_FLOW_WINDOWS-1:0] response_flow =
            i_im_recv_pc[dlane*_BITWIDTH_FLOW_WINDOWS_PC + IS_INST_PC_BITWIDTH +: _BITWIDTH_STRUCT_FLOW_WINDOWS];
        assign o_im_recv_discard[dlane] = i_im_recv_inst_valid[dlane] && flow_discard[response_flow];
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            next_pc <= '0;
            flow_id <= '0;
            flow_wait <= 1'b0;
            redirect_pending <= 1'b0;
            redirect_pc <= '0;
            next_order <= 1;
            flow_requested <= 0;
            retire_valid <= '0;
        end
        else begin
            next_pc <= next_pc_next;
            flow_id <= flow_id_next;
            flow_wait <= flow_wait_next;
            redirect_pending <= redirect_pending_next;
            redirect_pc <= redirect_pc_next;
            next_order <= next_order_next;
            flow_requested <= flow_requested_next;
            retire_valid <= retire_valid_next;
        end
    end

    for (genvar flow = 0; flow < STRUCT_FLOW_WINDOWS; flow++) begin : GEN_FLOW_DETECT_UNIT
        flow_detect_unit #(.INITIAL_ACTIVE(flow == 0)) U_FLOW_DETECT_UNIT (
            .clk(clk), .reset_n(reset_n),
            .i_active_next(flow_active_next[flow]),
            .i_closed_next(flow_closed_next[flow]),
            .i_discard_next(flow_discard_next[flow]),
            .i_pending_next(flow_pending_next[flow]),
            .i_inflight_next(flow_inflight_next[flow]),
            .i_order_next(flow_order_next[flow]),
            .o_active(flow_active[flow]),
            .o_closed(flow_closed[flow]),
            .o_discard(flow_discard[flow]),
            .o_pending(flow_pending[flow]),
            .o_inflight(flow_inflight[flow]),
            .o_order(flow_order[flow])
        );
    end

    for (genvar ridx = 0; ridx < RETIRE_DEPTH; ridx++) begin : GEN_RETIRE_DATA
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) retire_data[ridx] <= '0;
            else retire_data[ridx] <= retire_data_next[ridx];
        end
    end

endmodule
