`timescale 1ns/1ps
module instruction_state_table #(
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
    localparam int _BITWIDTH_STRUCT_JUMP_BRANCH_INFO    = 1 // Jump Register Flag
                                                         + 1 // Branch Flag
                                                         + IS_INST_PC_BITWIDTH, // New Program Counter
    localparam int _BITWIDTH_STRUCT_EX_DONE_PC          = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                                         + IS_INST_PC_BITWIDTH
) (
    input  logic                                                                                      clk,
    input  logic                                                                                      reset_n,

    // New Internal Instruction Input (NEL)
    input  logic [STRUCT_DECODE_NEW_INST-1:0]                                                         i_nel_new_inst_valid,
    output logic [STRUCT_DECODE_NEW_INST-1:0]                                                         o_nel_new_inst_get,
    input  logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_INTERNAL_INST_WIDTH))-1:0]                      i_nel_new_inst_data,

    // Ready Physical Registers Input (PRM)
    input  logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                                                        i_prm_ready_phyreg_valid,
    input  logic [(STRUCT_PRM_ENTRY_UPDATE *(_BITWIDTH_READY_PRM) )-1:0]                              i_prm_ready_phyreg_data,
    
    // Executable (All phyreg in instruction are ready) Internal Instruction Output (RS)
    output logic [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               o_rs_ready_inst_valid,
    input  logic [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                               i_rs_ready_inst_get,
    output logic [((STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)*_BITWIDTH_EX_INST_WIDTH)-1:0]     o_rs_ready_inst_data,

    // Wait Physical Registers Output (PRM)
    output logic [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]                                      o_prm_wait_phyreg_valid,
    output logic [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS*(_BITWIDTH_READY_PRM) )-1:0]               o_prm_wait_phyreg_data
);

    localparam int NEW_UPDATE_WIDTH        = STRUCT_PRM_ENTRY_UPDATE + STRUCT_DECODE_NEW_INST;
    localparam int STARTBIT_RS_PART        = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                           + IS_INST_PC_BITWIDTH
                                           + _BITWIDTH_STRUCT_EX_PATH
                                           + EX_INST_MICROOP_BITWIDTH
                                           + IS_INST_IMM
                                           + _BITWIDTH_STRUCT_PHYREGS;
    localparam int STARTBIT_REG_READY_PART = _BITWIDTH_STRUCT_FLOW_WINDOWS
                                           + IS_INST_PC_BITWIDTH
                                           + _BITWIDTH_STRUCT_EX_PATH
                                           + EX_INST_MICROOP_BITWIDTH
                                           + IS_INST_IMM
                                           + _BITWIDTH_STRUCT_PHYREGS // rd
                                           + (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS); // rs1..n
    
    localparam int _BITWIDTH_ALLOC_IST_NUM = _BITWIDTH_STRUCT_INST_STATE_ENTRIES*STRUCT_DECODE_NEW_INST;
    localparam int _BITWIDTH_PHY_RS_INST   = _BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS;

    logic [_BITWIDTH_INTERNAL_INST_WIDTH-1:0]                  target_internal_inst;
    logic [_BITWIDTH_EX_INST_WIDTH-1:0]                        target_ist_entry        [0:STRUCT_DECODE_NEW_INST-1];
    logic [(_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS)-1:0]  target_phyreg_source    [0:STRUCT_DECODE_NEW_INST-1];
    logic [IS_INST_OPERANDS-1:0]                               target_source_ready     [0:STRUCT_DECODE_NEW_INST-1];
    logic [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_EX_INST_WIDTH))-1:0]
                                                               nel_new_inst_data;

    logic [STRUCT_DECODE_NEW_INST-1:0]                         allocate_valid;
    logic [_BITWIDTH_ALLOC_IST_NUM-1:0]                        allocate_alloc_num_out;
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0]            allocate_alloc_num_list [0:STRUCT_DECODE_NEW_INST-1];
    logic [STRUCT_DECODE_NEW_INST-1:0]                         allocate_is_entries;
    logic [STRUCT_DECODE_NEW_INST-1:0]                         ready_is_entries;
    logic [(_BITWIDTH_PHY_RS_INST*STRUCT_DECODE_NEW_INST)-1:0] rs_phyregs;
    logic [STRUCT_DECODE_NEW_INST-1:0]                         ready_nel_update        [0:IS_INST_OPERANDS-1];

    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]                       prm_update_phyreg       [0:STRUCT_PRM_ENTRY_UPDATE-1];
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0]            prm_update_istnum       [0:STRUCT_PRM_ENTRY_UPDATE-1];
    logic [(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*STRUCT_PRM_ENTRY_UPDATE)-1:0]
                                                               prm_update_istnum_all;

    logic [(_BITWIDTH_PHY_RS_INST*STRUCT_PRM_ENTRY_UPDATE)-1:0] 
                                                               check_phyreg_all;

    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        ready_prm_update        [0:IS_INST_OPERANDS-1];
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        last_ready              [0:IS_INST_OPERANDS-1];
    logic [IS_INST_OPERANDS-1:0]                               ready_check_section;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        ready_prm_rs;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]                       ready_check_phyreg_target;

    logic                                                     nel_accept_enable;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        prm_update_write;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        unallocate_ready;
    logic [STRUCT_INST_STATE_ENTRIES-1:0]                     active_entries, active_entries_next;
    logic [STRUCT_INST_STATE_ENTRIES-1:0]                     pending_entries, pending_entries_next;
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0]           issue_start, issue_start_next;
    logic [(STRUCT_PRM_ENTRY_UPDATE*_BITWIDTH_STRUCT_INST_STATE_ENTRIES)-1:0]
                                                               issue_istnum_all;

    integer idx_internal_inst, idx_rs, idx_update, idx_entry;
    integer issue_entry, issue_channel;

    // Admission depends only on allocator offers and RS capacity. Keeping
    // this wiring outside the NEL-consuming block also makes that independence
    // visible to simulators when NEL gates its Valid with our Get.
    assign nel_accept_enable = reset_n &&
        (&allocate_valid) && (&i_rs_ready_inst_get);
    assign o_nel_new_inst_get = {STRUCT_DECODE_NEW_INST{nel_accept_enable}};

    // PRM read addresses are pure input wiring, independent of the ready checker.
    genvar prm_idx;
    generate
        for (prm_idx = 0; prm_idx < STRUCT_PRM_ENTRY_UPDATE; prm_idx = prm_idx+1) begin : G_PRM_INPUT
            assign prm_update_phyreg[prm_idx] =
                i_prm_ready_phyreg_data[(_BITWIDTH_READY_PRM*prm_idx) +: _BITWIDTH_STRUCT_PHYREGS];
            assign prm_update_istnum[prm_idx] =
                i_prm_ready_phyreg_data[(_BITWIDTH_READY_PRM*prm_idx)+_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES];
            assign prm_update_istnum_all[(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*prm_idx) +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] =
                prm_update_istnum[prm_idx];
        end
    endgenerate

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_entries  <= '0;
            pending_entries <= '0;
            issue_start     <= '0;
        end
        else begin
            active_entries  <= active_entries_next;
            pending_entries <= pending_entries_next;
            issue_start     <= issue_start_next;
        end
    end

    always_comb begin
        allocate_is_entries = '0; ready_is_entries = '0; ready_prm_rs = '0;
        active_entries_next  = active_entries;
        pending_entries_next = pending_entries;
        issue_start_next     = issue_start;
        issue_istnum_all     = '0;
        issue_entry          = 0;
        issue_channel        = 0;
        prm_update_write     = '0;
        ready_check_section  = '0;
        ready_check_phyreg_target = '0;

        for (idx_rs = 0; idx_rs < IS_INST_OPERANDS; idx_rs = idx_rs+1) begin
            ready_prm_update[idx_rs] = last_ready[idx_rs];
        end

        for (idx_internal_inst = 0; idx_internal_inst < STRUCT_DECODE_NEW_INST; idx_internal_inst = idx_internal_inst+1) begin
            // Split Allocate IST Numbers
            allocate_alloc_num_list[idx_internal_inst] = 
                allocate_alloc_num_out[(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*idx_internal_inst) +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES];

            // Split Inst
            target_internal_inst                       = 
                i_nel_new_inst_data[(_BITWIDTH_INTERNAL_INST_WIDTH*idx_internal_inst) +: _BITWIDTH_INTERNAL_INST_WIDTH];
            target_ist_entry[idx_internal_inst]        =
                target_internal_inst[0                       +: _BITWIDTH_EX_INST_WIDTH];
            target_phyreg_source[idx_internal_inst]    = 
                target_internal_inst[STARTBIT_RS_PART        +: (_BITWIDTH_STRUCT_PHYREGS * IS_INST_OPERANDS)];
            target_source_ready[idx_internal_inst]     = 
                target_internal_inst[STARTBIT_REG_READY_PART +: IS_INST_OPERANDS];

            // Set Allocate
            allocate_is_entries[idx_internal_inst]     = 
                !( &target_source_ready[idx_internal_inst] ) && i_nel_new_inst_valid[idx_internal_inst] && nel_accept_enable;
            ready_is_entries   [idx_internal_inst]     = 
                ( &target_source_ready[idx_internal_inst] ) && i_nel_new_inst_valid[idx_internal_inst] && nel_accept_enable;

            if (allocate_is_entries[idx_internal_inst]) begin
                active_entries_next[allocate_alloc_num_list[idx_internal_inst]]  = 1'b1;
                pending_entries_next[allocate_alloc_num_list[idx_internal_inst]] = 1'b0;
            end

            nel_new_inst_data[(_BITWIDTH_EX_INST_WIDTH*idx_internal_inst) +: _BITWIDTH_EX_INST_WIDTH] = 
                target_ist_entry[idx_internal_inst];

            o_rs_ready_inst_data[(STRUCT_PRM_ENTRY_UPDATE*_BITWIDTH_EX_INST_WIDTH)+(_BITWIDTH_EX_INST_WIDTH*idx_internal_inst) 
                +: _BITWIDTH_EX_INST_WIDTH] = target_ist_entry[idx_internal_inst];
        end

        for (idx_internal_inst = 0; idx_internal_inst < STRUCT_DECODE_NEW_INST; idx_internal_inst = idx_internal_inst+1) begin
            // Gather RS PHYREGs
            rs_phyregs[(_BITWIDTH_PHY_RS_INST*idx_internal_inst) +: _BITWIDTH_PHY_RS_INST] =
                target_phyreg_source[idx_internal_inst];

            // NEW Entry Readys
            for (idx_rs = 0; idx_rs < IS_INST_OPERANDS; idx_rs = idx_rs+1) begin
                ready_nel_update[idx_rs][idx_internal_inst] = target_source_ready[idx_internal_inst][idx_rs];
            end

            // Wait PRM
            for (idx_rs = 0; idx_rs < IS_INST_OPERANDS; idx_rs = idx_rs+1) begin
                o_prm_wait_phyreg_valid[(idx_internal_inst*IS_INST_OPERANDS)+idx_rs] 
                    = ~ready_nel_update[idx_rs][idx_internal_inst] & allocate_is_entries[idx_internal_inst];
                o_prm_wait_phyreg_data[(_BITWIDTH_READY_PRM*( (idx_internal_inst*IS_INST_OPERANDS)+idx_rs )) +: _BITWIDTH_READY_PRM]
                    = {allocate_alloc_num_list[idx_internal_inst], 
                       target_phyreg_source[idx_internal_inst][(_BITWIDTH_STRUCT_PHYREGS*idx_rs) +: _BITWIDTH_STRUCT_PHYREGS]};
            end
        end

        for (idx_internal_inst = 0; idx_internal_inst < STRUCT_PRM_ENTRY_UPDATE; idx_internal_inst = idx_internal_inst+1) begin
            // Only the first valid channel for an active IST entry writes it.
            // Merge every notification for that entry before the single write.
            if (reset_n && i_prm_ready_phyreg_valid[idx_internal_inst] &&
                (int'(prm_update_istnum[idx_internal_inst]) < STRUCT_INST_STATE_ENTRIES)) begin
                prm_update_write[idx_internal_inst] = active_entries[prm_update_istnum[idx_internal_inst]];
            end
            for (idx_update = 0; idx_update < idx_internal_inst; idx_update = idx_update+1) begin
                if (i_prm_ready_phyreg_valid[idx_update] &&
                    (prm_update_istnum[idx_update] == prm_update_istnum[idx_internal_inst])) begin
                    prm_update_write[idx_internal_inst] = 1'b0;
                end
            end

            for (idx_rs = 0; idx_rs < IS_INST_OPERANDS; idx_rs = idx_rs+1) begin
                ready_check_section[idx_rs] = last_ready[idx_rs][idx_internal_inst];
                ready_check_phyreg_target = 
                    check_phyreg_all[(_BITWIDTH_STRUCT_PHYREGS*((IS_INST_OPERANDS*idx_internal_inst)+idx_rs)) +: _BITWIDTH_STRUCT_PHYREGS];
                for (idx_update = 0; idx_update < STRUCT_PRM_ENTRY_UPDATE; idx_update = idx_update+1) begin
                    if (i_prm_ready_phyreg_valid[idx_update] &&
                        (prm_update_istnum[idx_update] == prm_update_istnum[idx_internal_inst]) &&
                        (ready_check_phyreg_target == prm_update_phyreg[idx_update])) begin
                        ready_check_section[idx_rs] = 1'b1;
                    end
                end
                ready_prm_update[idx_rs][idx_internal_inst] = ready_check_section[idx_rs];
            end

            // PRM sends pulses without Get. Retain completions even if RS stalls.
            if (prm_update_write[idx_internal_inst] && (&ready_check_section)) begin
                pending_entries_next[prm_update_istnum[idx_internal_inst]] = 1'b1;
            end
        end

        // Registered pending entries issue from the following cycle. Round-robin
        // selection prevents repeated low-index reuse from starving older entries.
        // RS transfer and allocator return happen together. Hold the pending
        // entry if either destination is unable to accept it.
        // Valid is a transfer pulse, as in NEL.
        for (idx_entry = 0; idx_entry < STRUCT_INST_STATE_ENTRIES; idx_entry = idx_entry+1) begin
            issue_entry = int'(issue_start) + idx_entry;
            if (issue_entry >= STRUCT_INST_STATE_ENTRIES) issue_entry = issue_entry - STRUCT_INST_STATE_ENTRIES;
            if (pending_entries[issue_entry] && (issue_channel < STRUCT_PRM_ENTRY_UPDATE)) begin
                issue_istnum_all[(issue_channel*_BITWIDTH_STRUCT_INST_STATE_ENTRIES) +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] =
                    _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(issue_entry);
                ready_prm_rs[issue_channel] = reset_n && i_rs_ready_inst_get[issue_channel] && unallocate_ready[issue_channel];
                if (ready_prm_rs[issue_channel]) begin
                    active_entries_next[issue_entry]  = 1'b0;
                    pending_entries_next[issue_entry] = 1'b0;
                    issue_start_next = (issue_entry == STRUCT_INST_STATE_ENTRIES-1)? '0 :
                        _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(issue_entry+1);
                end
                issue_channel = issue_channel+1;
            end
        end

        o_rs_ready_inst_valid   = {ready_is_entries, ready_prm_rs};
    end

    allocator #(
        .ENTRIES            (STRUCT_INST_STATE_ENTRIES),
        .START_VALUE        (0),
        .ALLOCATE_CHANNEL   (STRUCT_DECODE_NEW_INST),
        .UNALLOCATE_CHANNEL (STRUCT_PRM_ENTRY_UPDATE),
        .USE_BRAM           (1'b0)
    ) U_IST_ENTRY_ALLOCATOR (
        .clk                (clk),
        .reset_n            (reset_n),
        .i_flush            (1'b0),
        .i_unallocate       (ready_prm_rs),
        .o_unallocate_ready (unallocate_ready),
        .i_unallocate_data  (issue_istnum_all),
        .i_allocate         (allocate_is_entries),
        .o_allocate_valid   (allocate_valid),
        .o_allocate_data    (allocate_alloc_num_out)
    );

    regfile #(
        .DATA_WIDTH    (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS),
        .ENTRIES       (STRUCT_INST_STATE_ENTRIES),
        .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL (STRUCT_DECODE_NEW_INST),
        .INITIAL_VALUE (0)
    ) U_IST_SOURCE_TABLE (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0), // 지금은 분기가 없어..
        .i_read_addr   (prm_update_istnum_all),
        .o_read_data   (check_phyreg_all),
        .i_write_addr  (allocate_alloc_num_out),
        .i_write_en    (allocate_is_entries),
        .i_write_data  (rs_phyregs)
    );
    
    regfile #(
        .DATA_WIDTH    (_BITWIDTH_EX_INST_WIDTH),
        .ENTRIES       (STRUCT_INST_STATE_ENTRIES),
        .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL (STRUCT_DECODE_NEW_INST),
        .INITIAL_VALUE (0)
    ) U_IST_ENTRY_TABLE (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0), // 지금은 분기가 없어..
        .i_read_addr   (issue_istnum_all),
        .o_read_data   (o_rs_ready_inst_data[(STRUCT_PRM_ENTRY_UPDATE*_BITWIDTH_EX_INST_WIDTH)-1:0]),
        .i_write_addr  (allocate_alloc_num_out),
        .i_write_en    (allocate_is_entries),
        .i_write_data  (nel_new_inst_data)
    );

    genvar ready_rf_idx;

    generate
        for (ready_rf_idx = 0; ready_rf_idx < IS_INST_OPERANDS; ready_rf_idx = ready_rf_idx+1) begin
            regfile #(
                .DATA_WIDTH    (1),
                .ENTRIES       (STRUCT_INST_STATE_ENTRIES),
                .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
                .WRITE_CHANNEL (NEW_UPDATE_WIDTH),
                .INITIAL_VALUE (0)
            ) U_IST_READY_FLAGS_TABLE (
                .clk           (clk),
                .reset_n       (reset_n),
                .i_flush       (1'b0), // 지금은 분기가 없어..
                .i_read_addr   (prm_update_istnum_all),
                .o_read_data   (last_ready[ready_rf_idx]),
                .i_write_addr  ({prm_update_istnum_all         , allocate_alloc_num_out}),
                .i_write_en    ({prm_update_write             , allocate_is_entries}),
                .i_write_data  ({ready_prm_update[ready_rf_idx], ready_nel_update[ready_rf_idx]})
            );
        end
    endgenerate
    
endmodule
