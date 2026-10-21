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

    // Wakeup bandwidth, stored-instruction issue bandwidth and SRAM banking
    // are independent. Banks use low entry-number bits (power of two).
    parameter int STRUCT_IST_ISSUE_WIDTH               = STRUCT_EX_CORES,
    parameter int STRUCT_IST_BANKS                     = 1 << $clog2(
        (STRUCT_DECODE_NEW_INST > STRUCT_IST_ISSUE_WIDTH) ? STRUCT_DECODE_NEW_INST : STRUCT_IST_ISSUE_WIDTH),

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
    output logic [(STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH)-1:0]                               o_rs_ready_inst_valid,
    input  logic [(STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH)-1:0]                               i_rs_ready_inst_get,
    output logic [((STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH)*_BITWIDTH_EX_INST_WIDTH)-1:0]     o_rs_ready_inst_data,

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
    logic [STRUCT_DECODE_NEW_INST-1:0]                         allocate_valid;
    logic [_BITWIDTH_ALLOC_IST_NUM-1:0]                        allocate_alloc_num_out;
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0]            allocate_alloc_num_list [0:STRUCT_DECODE_NEW_INST-1];
    logic [STRUCT_DECODE_NEW_INST-1:0]                         allocate_is_entries;
    logic [STRUCT_DECODE_NEW_INST-1:0]                         ready_is_entries;
    logic [STRUCT_DECODE_NEW_INST-1:0]                         bypass_valid, bypass_valid_next;
    logic [(STRUCT_DECODE_NEW_INST*_BITWIDTH_EX_INST_WIDTH)-1:0] bypass_data, bypass_data_next;
    logic [STRUCT_DECODE_NEW_INST-1:0] bypass_reserve_valid, bypass_reserve_valid_next;
    logic [(STRUCT_DECODE_NEW_INST*_BITWIDTH_EX_INST_WIDTH)-1:0] bypass_reserve_data, bypass_reserve_data_next;
    logic [(_BITWIDTH_PHY_RS_INST*STRUCT_DECODE_NEW_INST)-1:0] rs_phyregs;
    logic [STRUCT_DECODE_NEW_INST-1:0]                         ready_nel_update        [0:IS_INST_OPERANDS-1];

    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0]            prm_update_istnum       [0:STRUCT_PRM_ENTRY_UPDATE-1];
    logic [(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*STRUCT_PRM_ENTRY_UPDATE)-1:0]
                                                               prm_update_istnum_all;

    logic [(_BITWIDTH_PHY_RS_INST*STRUCT_PRM_ENTRY_UPDATE)-1:0] 
                                                               check_phyreg_all;

    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        ready_prm_update        [0:IS_INST_OPERANDS-1];
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        last_ready              [0:IS_INST_OPERANDS-1];
    logic [IS_INST_OPERANDS-1:0]                               ready_check_section;

    logic                                                     nel_accept_enable;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        prm_update_write;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0] prm_stage_valid, prm_stage_valid_next;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0] raw_prm_phyreg [STRUCT_PRM_ENTRY_UPDATE];
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] raw_prm_entry [STRUCT_PRM_ENTRY_UPDATE];
    wire [STRUCT_PRM_ENTRY_UPDATE*_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] raw_prm_entry_all;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0] prm_hit [IS_INST_OPERANDS], prm_hit_next [IS_INST_OPERANDS];
    logic [STRUCT_INST_STATE_ENTRIES-1:0]                     active_entries, active_entries_next;
    logic [STRUCT_INST_STATE_ENTRIES-1:0]                     pending_entries, pending_entries_next;
    localparam int BANK_BITS = $clog2(STRUCT_IST_BANKS);
    localparam int BANK_WIDTH = (BANK_BITS > 0) ? BANK_BITS : 1;
    localparam int BANK_ROWS = (STRUCT_INST_STATE_ENTRIES+STRUCT_IST_BANKS-1)/STRUCT_IST_BANKS;
    localparam int ROW_WIDTH = (BANK_ROWS > 1) ? $clog2(BANK_ROWS) : 1;
    localparam int ALLOC_WIDTH = STRUCT_DECODE_NEW_INST*(_BITWIDTH_STRUCT_INST_STATE_ENTRIES+1);
    localparam int FREE_COUNT_WIDTH = $clog2(BANK_ROWS+1);
    localparam int FREE_ROW_LEAVES = 1 << $clog2(BANK_ROWS);
    localparam int ALLOC_CAND_WIDTH = FREE_COUNT_WIDTH+BANK_WIDTH+_BITWIDTH_STRUCT_INST_STATE_ENTRIES;
    localparam int FREE_BANK_COUNT_WIDTH = $clog2(STRUCT_IST_BANKS+1);

    logic [STRUCT_INST_STATE_ENTRIES-1:0] queued_entries, queued_entries_next;
    logic [BANK_ROWS-1:0] pending_pick [STRUCT_IST_BANKS];
    logic [ROW_WIDTH-1:0] pending_pick_row [STRUCT_IST_BANKS];
    logic [BANK_WIDTH-1:0] alloc_start, alloc_start_next, response_start, response_start_next;
    logic [STRUCT_IST_BANKS-1:0] bank_write, bank_read, bank_response_valid, bank_response_valid_next, bank_take;
    logic [ROW_WIDTH-1:0] bank_write_row [STRUCT_IST_BANKS];
    logic [ROW_WIDTH-1:0] bank_read_row [STRUCT_IST_BANKS];
    logic [_BITWIDTH_EX_INST_WIDTH-1:0] bank_write_data [STRUCT_IST_BANKS];
    wire [_BITWIDTH_EX_INST_WIDTH-1:0] bank_read_data [STRUCT_IST_BANKS];
    logic [ROW_WIDTH-1:0] bank_response_row [STRUCT_IST_BANKS], bank_response_row_next [STRUCT_IST_BANKS];
    // Two-entry, one-enqueue/one-dequeue address FIFO per bank.
    logic [1:0] request_count [STRUCT_IST_BANKS], request_count_next [STRUCT_IST_BANKS];
    logic [ROW_WIDTH-1:0] request_row [STRUCT_IST_BANKS][2], request_row_next [STRUCT_IST_BANKS][2];
    logic [ROW_WIDTH-1:0] pending_start [STRUCT_IST_BANKS], pending_start_next [STRUCT_IST_BANKS];
    logic [STRUCT_IST_ISSUE_WIDTH-1:0] issue_valid, issue_valid_next;
    logic [STRUCT_IST_ISSUE_WIDTH*_BITWIDTH_EX_INST_WIDTH-1:0] issue_data, issue_data_next;
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] issue_num [STRUCT_IST_ISSUE_WIDTH], issue_num_next [STRUCT_IST_ISSUE_WIDTH];
    // Two entries per issue lane: visible head plus one prefetched reserve.
    // Arbitration uses reserve_valid only, never the current RS Get. A full
    // lane may resume prefetch one cycle after popping, without a ready chain.
    logic [STRUCT_IST_ISSUE_WIDTH-1:0] reserve_valid, reserve_valid_next;
    logic [STRUCT_IST_ISSUE_WIDTH*_BITWIDTH_EX_INST_WIDTH-1:0] reserve_data, reserve_data_next;
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] reserve_num [STRUCT_IST_ISSUE_WIDTH], reserve_num_next [STRUCT_IST_ISSUE_WIDTH];
    localparam int RESPONSE_RANK_WIDTH = $clog2(STRUCT_IST_BANKS+STRUCT_IST_ISSUE_WIDTH+1);
    localparam int ISSUE_RANK_STAGES = $clog2(STRUCT_IST_ISSUE_WIDTH);
    logic [RESPONSE_RANK_WIDTH-1:0] bank_rank [BANK_BITS+1][STRUCT_IST_BANKS];
    logic [RESPONSE_RANK_WIDTH-1:0] lane_rank [ISSUE_RANK_STAGES+1][STRUCT_IST_ISSUE_WIDTH];
    logic [STRUCT_IST_BANKS-1:0] rotated_response_valid;
    integer idx_internal_inst, idx_rs, idx_update, idx_entry;
    integer selected_bank, candidate_bank;

    initial begin
        if (STRUCT_IST_ISSUE_WIDTH < 1 || STRUCT_IST_BANKS < STRUCT_DECODE_NEW_INST ||
            (STRUCT_IST_BANKS & (STRUCT_IST_BANKS-1)) != 0 || STRUCT_INST_STATE_ENTRIES < STRUCT_DECODE_NEW_INST)
            $fatal(1, "IST requires positive issue width, power-of-two banks >= decode, entries >= decode");
    end

    // Compare priority keys in parallel, then count higher-priority banks
    // with a balanced tree. Rotation makes every key unique, including ties
    // in free capacity. Addresses never traverse cascaded compare/swap muxes.
    function automatic logic [FREE_BANK_COUNT_WIDTH-1:0] prepared_rank(
        input logic [STRUCT_IST_BANKS*ALLOC_CAND_WIDTH-1:0] packed_candidates,
        input int bank
    );
        logic [FREE_BANK_COUNT_WIDTH-1:0] count_tree [2*STRUCT_IST_BANKS];
        logic [FREE_COUNT_WIDTH+BANK_WIDTH-1:0] key;
        key = packed_candidates[bank*ALLOC_CAND_WIDTH+_BITWIDTH_STRUCT_INST_STATE_ENTRIES
                                +: FREE_COUNT_WIDTH+BANK_WIDTH];
        count_tree[0] = '0;
        for (int b=0; b<STRUCT_IST_BANKS; b++)
            count_tree[STRUCT_IST_BANKS+b] = FREE_BANK_COUNT_WIDTH'(
                packed_candidates[b*ALLOC_CAND_WIDTH+_BITWIDTH_STRUCT_INST_STATE_ENTRIES
                                  +: FREE_COUNT_WIDTH+BANK_WIDTH] > key);
        for (int node=STRUCT_IST_BANKS-1; node>0; node--)
            count_tree[node] = count_tree[2*node]+count_tree[2*node+1];
        return count_tree[1];
    endfunction

    function automatic logic [ALLOC_WIDTH-1:0] rank_prepared(
        input logic [STRUCT_IST_BANKS*ALLOC_CAND_WIDTH-1:0] packed_candidates
    );
        logic [FREE_BANK_COUNT_WIDTH-1:0] rank [STRUCT_IST_BANKS];
        logic [ALLOC_WIDTH-1:0] result;
        logic chosen;
        result = '0; chosen = 0;
        for (int b=0; b<STRUCT_IST_BANKS; b++) rank[b] = prepared_rank(packed_candidates,b);
        for (int lane=0; lane<STRUCT_DECODE_NEW_INST; lane++) begin
            for (int b=0; b<STRUCT_IST_BANKS; b++) begin
                chosen = rank[b] == FREE_BANK_COUNT_WIDTH'(lane) &&
                    packed_candidates[b*ALLOC_CAND_WIDTH+_BITWIDTH_STRUCT_INST_STATE_ENTRIES+BANK_WIDTH
                                      +: FREE_COUNT_WIDTH] != 0;
                result[_BITWIDTH_ALLOC_IST_NUM+lane] |= chosen;
                result[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] |=
                    packed_candidates[b*ALLOC_CAND_WIDTH +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] &
                    {_BITWIDTH_STRUCT_INST_STATE_ENTRIES{chosen}};
            end
        end
        return result;
    endfunction

    // Combinational reference helper for allocation-policy equivalence tests.
    // Production allocation registers the preparation and ranking separately.
    // Prefer banks with more free rows; rotate equal-capacity choices. This
    // balances partial/sparse allocations and masks padding in the final row.
    function automatic logic [ALLOC_WIDTH-1:0] allocation_offers(
        input logic [STRUCT_INST_STATE_ENTRIES-1:0] active,
        input logic [BANK_WIDTH-1:0] start_bank
    );
        logic [FREE_COUNT_WIDTH-1:0] count_tree [2*FREE_ROW_LEAVES];
        logic [ROW_WIDTH-1:0] row_tree [2*FREE_ROW_LEAVES];
        logic [STRUCT_IST_BANKS*ALLOC_CAND_WIDTH-1:0] candidates;
        logic [BANK_WIDTH-1:0] bank_distance;
        bank_distance = '0;
        // Each bank reduces its free-row bitmap independently. Count addition
        // and first-free selection have logarithmic depth, not a row scan.
        for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
            count_tree[0] = '0; row_tree[0] = '0;
            for (int r = 0; r < FREE_ROW_LEAVES; r++) begin
                count_tree[FREE_ROW_LEAVES+r] = '0;
                row_tree[FREE_ROW_LEAVES+r] = '0;
                if (r < BANK_ROWS && (r*STRUCT_IST_BANKS+b) < STRUCT_INST_STATE_ENTRIES) begin
                    count_tree[FREE_ROW_LEAVES+r] = FREE_COUNT_WIDTH'(!active[r*STRUCT_IST_BANKS+b]);
                    row_tree[FREE_ROW_LEAVES+r] = ROW_WIDTH'(r);
                end
            end
            for (int node = FREE_ROW_LEAVES-1; node > 0; node--) begin
                count_tree[node] = count_tree[2*node]+count_tree[2*node+1];
                row_tree[node] = (count_tree[2*node] != 0) ? row_tree[2*node] : row_tree[2*node+1];
            end
            // Descending key: more space first, then nearest bank in the
            // start_bank rotation. Distances are unique, so ties are stable.
            bank_distance = BANK_WIDTH'(b)-start_bank;
            candidates[b*ALLOC_CAND_WIDTH +: ALLOC_CAND_WIDTH] = {count_tree[1], ~bank_distance,
                _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(int'(row_tree[1])*STRUCT_IST_BANKS+b)};
        end
        return rank_prepared(candidates);
    endfunction
    // Allocation pipeline: bank-local free-row preparation -> ranked grants
    // -> NEL write. Candidate and grant tokens own their rows until consumed.
    // Only registered ownership feeds preparation; same-cycle release/accept
    // cannot propagate back through the count/sort network into SRAM writes.
    logic [STRUCT_IST_BANKS-1:0] candidate_valid, candidate_take;
    logic [ROW_WIDTH-1:0] candidate_row_reg [STRUCT_IST_BANKS];
    logic [FREE_COUNT_WIDTH-1:0] candidate_count [STRUCT_IST_BANKS];
    logic [FREE_COUNT_WIDTH-1:0] prepare_count [STRUCT_IST_BANKS];
    logic [ROW_WIDTH-1:0] prepare_row [STRUCT_IST_BANKS];
    logic [STRUCT_INST_STATE_ENTRIES-1:0] allocation_reserved, allocation_unavailable;
    logic [1:0] grant_valid, grant_count;
    logic grant_read_ptr, grant_write_ptr, grant_push, grant_pop;
    logic [_BITWIDTH_ALLOC_IST_NUM-1:0] grant_data [2];
    logic [ALLOC_WIDTH-1:0] ranked_grant;
    logic [STRUCT_IST_BANKS*ALLOC_CAND_WIDTH-1:0] prepared_candidates;
    wire [FREE_BANK_COUNT_WIDTH-1:0] available_tree [2*STRUCT_IST_BANKS];
    assign available_tree[0] = '0;
    for (genvar b=0; b<STRUCT_IST_BANKS; b++) begin : G_GRANT_ELIGIBLE
        wire eligible = candidate_valid[b] && candidate_count[b] != 0;
        assign available_tree[STRUCT_IST_BANKS+b] = FREE_BANK_COUNT_WIDTH'(eligible);
        // Return selection directly to the originating bank, without decoding
        // an address that has already passed through the grant data mux.
        assign candidate_take[b] = grant_push && eligible &&
            prepared_rank(prepared_candidates,b) < FREE_BANK_COUNT_WIDTH'(STRUCT_DECODE_NEW_INST);
    end
    for (genvar node=1; node<STRUCT_IST_BANKS; node++) begin : G_GRANT_CAPACITY
        assign available_tree[node] = available_tree[2*node]+available_tree[2*node+1];
    end


    always_comb begin
        allocation_reserved = '0;
        for (int b = 0; b < STRUCT_IST_BANKS; b++)
            if (candidate_valid[b]) allocation_reserved[int'(candidate_row_reg[b])*STRUCT_IST_BANKS+b] = 1'b1;
        for (int q = 0; q < 2; q++)
            if (grant_valid[q])
                for (int lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++)
                    allocation_reserved[grant_data[q][lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES]] = 1'b1;
    end
    assign allocation_unavailable = active_entries | allocation_reserved;
    for (genvar b = 0; b < STRUCT_IST_BANKS; b++) begin : G_FREE_PREPARE
        logic [FREE_COUNT_WIDTH-1:0] count_tree [2*FREE_ROW_LEAVES];
        logic [ROW_WIDTH-1:0] row_tree [2*FREE_ROW_LEAVES];
        always_comb begin
            count_tree[0] = '0; row_tree[0] = '0;
            for (int r = 0; r < FREE_ROW_LEAVES; r++) begin
                count_tree[FREE_ROW_LEAVES+r] = '0;
                row_tree[FREE_ROW_LEAVES+r] = ROW_WIDTH'(r);
                if (r < BANK_ROWS && r*STRUCT_IST_BANKS+b < STRUCT_INST_STATE_ENTRIES)
                    count_tree[FREE_ROW_LEAVES+r] = FREE_COUNT_WIDTH'(!allocation_unavailable[r*STRUCT_IST_BANKS+b]);
            end
            for (int node = FREE_ROW_LEAVES-1; node > 0; node--) begin
                count_tree[node] = count_tree[2*node]+count_tree[2*node+1];
                row_tree[node] = count_tree[2*node] != 0 ? row_tree[2*node] : row_tree[2*node+1];
            end
            prepare_count[b] = count_tree[1]; prepare_row[b] = row_tree[1];
        end
        wire [BANK_WIDTH-1:0] distance_from_start = BANK_WIDTH'(b)-alloc_start;
        assign prepared_candidates[b*ALLOC_CAND_WIDTH +: ALLOC_CAND_WIDTH] = {
            candidate_valid[b] ? candidate_count[b] : FREE_COUNT_WIDTH'(0),
            ~distance_from_start,
            _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(int'(candidate_row_reg[b])*STRUCT_IST_BANKS+b)};
    end
    assign ranked_grant = rank_prepared(prepared_candidates);
    assign grant_push = reset_n && grant_count < 2 &&
        available_tree[1] >= FREE_BANK_COUNT_WIDTH'(STRUCT_DECODE_NEW_INST);
    assign grant_pop = nel_accept_enable && (|i_nel_new_inst_valid);
    assign allocate_valid = {STRUCT_DECODE_NEW_INST{reset_n && grant_count != 0}};
    assign allocate_alloc_num_out = grant_data[grant_read_ptr];
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            candidate_valid <= '0; grant_valid <= '0; grant_count <= '0;
            grant_read_ptr <= 0; grant_write_ptr <= 0;
            for (int q = 0; q < 2; q++) grant_data[q] <= '0;
            for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
                candidate_row_reg[b] <= '0; candidate_count[b] <= '0;
            end
        end else begin
            grant_count <= grant_count+2'(grant_push)-2'(grant_pop);
            if (grant_pop) begin
                grant_valid[grant_read_ptr] <= 0; grant_read_ptr <= ~grant_read_ptr;
            end
            if (grant_push) begin
                grant_data[grant_write_ptr] <= ranked_grant[0 +: _BITWIDTH_ALLOC_IST_NUM];
                grant_valid[grant_write_ptr] <= 1; grant_write_ptr <= ~grant_write_ptr;
            end
            for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
                candidate_count[b] <= prepare_count[b]+FREE_COUNT_WIDTH'(candidate_valid[b] && !candidate_take[b]);
                if (!candidate_valid[b] || candidate_take[b]) begin
                    candidate_valid[b] <= prepare_count[b] != 0;
                    if (prepare_count[b] != 0) candidate_row_reg[b] <= prepare_row[b];
                end
            end
        end
    end


    // Reference capacity helper for the allocation-policy tests.
    function automatic logic allocation_capacity(
        input logic [STRUCT_INST_STATE_ENTRIES-1:0] active
    );
        logic [BANK_ROWS-1:0] free_rows;
        logic [FREE_BANK_COUNT_WIDTH-1:0] bank_count [2*STRUCT_IST_BANKS];
        free_rows = '0;
        bank_count[0] = '0;
        for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
            free_rows = '0;
            for (int r = 0; r < BANK_ROWS; r++) begin
                if (r*STRUCT_IST_BANKS+b < STRUCT_INST_STATE_ENTRIES)
                    free_rows[r] = !active[r*STRUCT_IST_BANKS+b];
            end
            bank_count[STRUCT_IST_BANKS+b] = FREE_BANK_COUNT_WIDTH'(|free_rows);
        end
        for (int node = STRUCT_IST_BANKS-1; node > 0; node--)
            bank_count[node] = bank_count[2*node]+bank_count[2*node+1];
        return bank_count[1] >= FREE_BANK_COUNT_WIDTH'(STRUCT_DECODE_NEW_INST);
    endfunction

    // Two slots per bypass lane reserve one whole incoming bundle using only
    // registered occupancy. RS Get cannot propagate into NEL admission.
    assign nel_accept_enable = reset_n && (&allocate_valid) && !(|bypass_reserve_valid);
    assign o_nel_new_inst_get = {STRUCT_DECODE_NEW_INST{nel_accept_enable}};

    // Notification stage A: source lookup and operand matching. Only identity
    // and newly completed operand bits cross the register; ready flags are read
    // LIVE in stage B, so adjacent notifications never overwrite prior progress.
    for (genvar p = 0; p < STRUCT_PRM_ENTRY_UPDATE; p++) begin : G_PRM_INPUT
        assign raw_prm_phyreg[p] = i_prm_ready_phyreg_data[p*_BITWIDTH_READY_PRM +: _BITWIDTH_STRUCT_PHYREGS];
        assign raw_prm_entry[p] = i_prm_ready_phyreg_data[p*_BITWIDTH_READY_PRM+_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES];
        assign raw_prm_entry_all[p*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] = raw_prm_entry[p];
        assign prm_update_istnum_all[p*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] = prm_update_istnum[p];
    end
    always_comb begin
        prm_stage_valid_next = '0;
        for (int operand = 0; operand < IS_INST_OPERANDS; operand++) prm_hit_next[operand] = '0;
        for (int p = 0; p < STRUCT_PRM_ENTRY_UPDATE; p++) begin
            if (reset_n && i_prm_ready_phyreg_valid[p] && int'(raw_prm_entry[p]) < STRUCT_INST_STATE_ENTRIES)
                prm_stage_valid_next[p] = active_entries[raw_prm_entry[p]];
            for (int operand = 0; operand < IS_INST_OPERANDS; operand++) begin
                for (int other = 0; other < STRUCT_PRM_ENTRY_UPDATE; other++) begin
                    if (i_prm_ready_phyreg_valid[other] && raw_prm_entry[p] == raw_prm_entry[other] &&
                        check_phyreg_all[(p*IS_INST_OPERANDS+operand)*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS] == raw_prm_phyreg[other])
                        prm_hit_next[operand][p] = 1'b1;
                end
            end
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            prm_stage_valid <= '0;
            for (int operand = 0; operand < IS_INST_OPERANDS; operand++) prm_hit[operand] <= '0;
            for (int p = 0; p < STRUCT_PRM_ENTRY_UPDATE; p++) prm_update_istnum[p] <= '0;
        end else begin
            prm_stage_valid <= prm_stage_valid_next;
            for (int operand = 0; operand < IS_INST_OPERANDS; operand++) prm_hit[operand] <= prm_hit_next[operand];
            for (int p = 0; p < STRUCT_PRM_ENTRY_UPDATE; p++) prm_update_istnum[p] <= raw_prm_entry[p];
        end
    end

    // Bank-local balanced first-set trees, with direct one-hot state updates.
    // The request address encoder is not on the queued/pending feedback path.
    function automatic logic [BANK_ROWS-1:0] first_pending(input logic [BANK_ROWS-1:0] bits_in);
        logic [BANK_ROWS-1:0] tree [2*FREE_ROW_LEAVES];
        for (int leaf = 0; leaf < FREE_ROW_LEAVES; leaf++) begin
            tree[FREE_ROW_LEAVES+leaf] = '0;
            if (leaf < BANK_ROWS) tree[FREE_ROW_LEAVES+leaf][leaf] = bits_in[leaf];
        end
        for (int node = FREE_ROW_LEAVES-1; node > 0; node--)
            tree[node] = (|tree[2*node]) ? tree[2*node] : tree[2*node+1];
        return tree[1];
    endfunction
    for (genvar b = 0; b < STRUCT_IST_BANKS; b++) begin : G_PENDING_SELECT
        logic [BANK_ROWS-1:0] eligible, after_cursor, preferred;
        always_comb begin
            eligible = '0; after_cursor = '0;
            for (int row = 0; row < BANK_ROWS; row++) begin
                if (row*STRUCT_IST_BANKS+b < STRUCT_INST_STATE_ENTRIES) begin
                    eligible[row] = pending_entries[row*STRUCT_IST_BANKS+b] && !queued_entries[row*STRUCT_IST_BANKS+b];
                    after_cursor[row] = eligible[row] && ROW_WIDTH'(row) >= pending_start[b];
                end
            end
            preferred = first_pending(after_cursor);
            pending_pick[b] = (|after_cursor) ? preferred : first_pending(eligible);
            pending_pick_row[b] = '0;
            for (int row = 0; row < BANK_ROWS; row++)
                pending_pick_row[b] |= {ROW_WIDTH{pending_pick[b][row]}} & ROW_WIDTH'(row);
        end
    end

    // Parallel prefix ranks replace cascaded per-lane bank selection. Match
    // the kth available bank to the kth lane with reserve space. Both masks
    // depend only on registers, so RS Get cannot reach bank_take / SRAM reads.
    always_comb begin
        for (int offset = 0; offset < STRUCT_IST_BANKS; offset++) begin
            rotated_response_valid[offset] = bank_response_valid[(int'(response_start)+offset) % STRUCT_IST_BANKS];
            bank_rank[0][offset] = RESPONSE_RANK_WIDTH'(rotated_response_valid[offset]);
        end
        for (int stage_idx = 0; stage_idx < BANK_BITS; stage_idx++) begin
            for (int offset = 0; offset < STRUCT_IST_BANKS; offset++) begin
                bank_rank[stage_idx+1][offset] = bank_rank[stage_idx][offset];
                if (offset >= (1 << stage_idx))
                    bank_rank[stage_idx+1][offset] = bank_rank[stage_idx][offset]+bank_rank[stage_idx][offset-(1 << stage_idx)];
            end
        end
        for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++)
            lane_rank[0][lane] = RESPONSE_RANK_WIDTH'(!reserve_valid[lane]);
        for (int stage_idx = 0; stage_idx < ISSUE_RANK_STAGES; stage_idx++) begin
            for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) begin
                lane_rank[stage_idx+1][lane] = lane_rank[stage_idx][lane];
                if (lane >= (1 << stage_idx))
                    lane_rank[stage_idx+1][lane] = lane_rank[stage_idx][lane]+lane_rank[stage_idx][lane-(1 << stage_idx)];
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_entries <= '0; pending_entries <= '0; queued_entries <= '0;
            bypass_valid <= '0; bypass_data <= '0;
            bypass_reserve_valid <= '0; bypass_reserve_data <= '0;
            alloc_start <= '0; response_start <= '0;
            bank_response_valid <= '0;
            issue_valid <= '0; issue_data <= '0;
            reserve_valid <= '0; reserve_data <= '0;
            for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
                bank_response_row[b] <= '0; request_count[b] <= '0; pending_start[b] <= '0;
                for (int q = 0; q < 2; q++) request_row[b][q] <= '0;
            end
            for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) begin
                issue_num[lane] <= '0; reserve_num[lane] <= '0;
            end
        end
        else begin
            active_entries <= active_entries_next; pending_entries <= pending_entries_next;
            queued_entries <= queued_entries_next;
            bypass_valid <= bypass_valid_next; bypass_data <= bypass_data_next;
            bypass_reserve_valid <= bypass_reserve_valid_next; bypass_reserve_data <= bypass_reserve_data_next;
            alloc_start <= alloc_start_next; response_start <= response_start_next;
            bank_response_valid <= bank_response_valid_next;
            issue_valid <= issue_valid_next; issue_data <= issue_data_next;
            reserve_valid <= reserve_valid_next; reserve_data <= reserve_data_next;
            for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
                bank_response_row[b] <= bank_response_row_next[b];
                request_count[b] <= request_count_next[b]; pending_start[b] <= pending_start_next[b];
                for (int q = 0; q < 2; q++) request_row[b][q] <= request_row_next[b][q];
            end
            for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) begin
                issue_num[lane] <= issue_num_next[lane]; reserve_num[lane] <= reserve_num_next[lane];
            end
        end
    end

    always_comb begin
        allocate_is_entries = '0; ready_is_entries = '0;
        active_entries_next  = active_entries;
        pending_entries_next = pending_entries;
        prm_update_write     = '0;
        ready_check_section  = '0;
        bypass_valid_next = bypass_valid & ~i_rs_ready_inst_get[STRUCT_IST_ISSUE_WIDTH +: STRUCT_DECODE_NEW_INST];
        bypass_data_next = bypass_data;
        bypass_reserve_valid_next = bypass_reserve_valid;
        bypass_reserve_data_next = bypass_reserve_data;
        for (int lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
            if (!bypass_valid_next[lane] && bypass_reserve_valid[lane]) begin
                bypass_valid_next[lane] = 1'b1;
                bypass_data_next[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] =
                    bypass_reserve_data[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH];
                bypass_reserve_valid_next[lane] = 1'b0;
            end
        end
        queued_entries_next = queued_entries;
        alloc_start_next = alloc_start; response_start_next = response_start;
        bank_write = '0; bank_read = '0; bank_take = '0;
        bank_response_valid_next = bank_response_valid;
        issue_valid_next = issue_valid & ~i_rs_ready_inst_get[STRUCT_IST_ISSUE_WIDTH-1:0];
        issue_data_next = issue_data;
        reserve_valid_next = reserve_valid; reserve_data_next = reserve_data;
        selected_bank = -1; candidate_bank = 0;
        for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
            bank_write_row[b] = '0; bank_write_data[b] = '0;
            bank_read_row[b] = bank_response_row[b];
            bank_response_row_next[b] = bank_response_row[b];
            request_count_next[b] = request_count[b]; pending_start_next[b] = pending_start[b];
            for (int q = 0; q < 2; q++) request_row_next[b][q] = request_row[b][q];
        end
        for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) begin
            issue_num_next[lane] = issue_num[lane]; reserve_num_next[lane] = reserve_num[lane];
        end

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
                queued_entries_next[allocate_alloc_num_list[idx_internal_inst]] = 1'b0;
                bank_write[int'(allocate_alloc_num_list[idx_internal_inst]) % STRUCT_IST_BANKS] = 1'b1;
                bank_write_row[int'(allocate_alloc_num_list[idx_internal_inst]) % STRUCT_IST_BANKS] =
                    ROW_WIDTH'(allocate_alloc_num_list[idx_internal_inst] >> BANK_BITS);
                bank_write_data[int'(allocate_alloc_num_list[idx_internal_inst]) % STRUCT_IST_BANKS] = target_ist_entry[idx_internal_inst];
                alloc_start_next = BANK_WIDTH'((int'(allocate_alloc_num_list[idx_internal_inst])+1) % STRUCT_IST_BANKS);
            end

            if (ready_is_entries[idx_internal_inst]) begin
                if (!bypass_valid_next[idx_internal_inst]) begin
                    bypass_valid_next[idx_internal_inst] = 1'b1;
                    bypass_data_next[idx_internal_inst*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] = target_ist_entry[idx_internal_inst];
                end else begin
                    bypass_reserve_valid_next[idx_internal_inst] = 1'b1;
                    bypass_reserve_data_next[idx_internal_inst*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] = target_ist_entry[idx_internal_inst];
                end
            end
            o_rs_ready_inst_data[(STRUCT_IST_ISSUE_WIDTH*_BITWIDTH_EX_INST_WIDTH)+(_BITWIDTH_EX_INST_WIDTH*idx_internal_inst)
                +: _BITWIDTH_EX_INST_WIDTH] = bypass_data[idx_internal_inst*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH];
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
            if (reset_n && prm_stage_valid[idx_internal_inst] &&
                (int'(prm_update_istnum[idx_internal_inst]) < STRUCT_INST_STATE_ENTRIES)) begin
                prm_update_write[idx_internal_inst] = active_entries[prm_update_istnum[idx_internal_inst]];
            end
            for (idx_update = 0; idx_update < idx_internal_inst; idx_update = idx_update+1) begin
                if (prm_stage_valid[idx_update] &&
                    (prm_update_istnum[idx_update] == prm_update_istnum[idx_internal_inst])) begin
                    prm_update_write[idx_internal_inst] = 1'b0;
                end
            end

            for (idx_rs = 0; idx_rs < IS_INST_OPERANDS; idx_rs = idx_rs+1) begin
                ready_check_section[idx_rs] = last_ready[idx_rs][idx_internal_inst] | prm_hit[idx_rs][idx_internal_inst];
                ready_prm_update[idx_rs][idx_internal_inst] = ready_check_section[idx_rs];
            end

            // PRM sends pulses without Get. Retain completions even if RS stalls.
            if (prm_update_write[idx_internal_inst] && (&ready_check_section) &&
                !queued_entries[prm_update_istnum[idx_internal_inst]]) begin
                pending_entries_next[prm_update_istnum[idx_internal_inst]] = 1'b1;
            end
        end

        // RS only consumes prepared heads. A stalled head retains its exact
        // payload; a reserve moves forward on consumption. Keep IST ownership
        // until this handshake, including instructions held in reserves.
        for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) begin
            if (issue_valid[lane] && i_rs_ready_inst_get[lane]) begin
                active_entries_next[issue_num[lane]] = 1'b0;
                pending_entries_next[issue_num[lane]] = 1'b0;
                queued_entries_next[issue_num[lane]] = 1'b0;
                issue_valid_next[lane] = reserve_valid[lane];
                if (reserve_valid[lane]) begin
                    issue_data_next[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] =
                        reserve_data[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH];
                    issue_num_next[lane] = reserve_num[lane];
                end
                reserve_valid_next[lane] = 1'b0;
            end
            // Reserve space is tested BEFORE this cycle's pop. A late Get
            // changes only where the prefetched payload lands, not selection.
            if (reset_n && !reserve_valid[lane]) begin
                selected_bank = -1;
                for (int offset = 0; offset < STRUCT_IST_BANKS; offset++) begin
                    candidate_bank = (int'(response_start)+offset) % STRUCT_IST_BANKS;
                    if (rotated_response_valid[offset] &&
                        bank_rank[BANK_BITS][offset] == lane_rank[ISSUE_RANK_STAGES][lane])
                        selected_bank = candidate_bank;
                end
                if (selected_bank >= 0) begin
                    bank_take[selected_bank] = 1'b1;
                    if (!issue_valid_next[lane]) begin
                        issue_valid_next[lane] = 1'b1;
                        issue_data_next[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] = bank_read_data[selected_bank];
                        issue_num_next[lane] = _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(
                            int'(bank_response_row[selected_bank])*STRUCT_IST_BANKS+selected_bank);
                    end
                    else begin
                        reserve_valid_next[lane] = 1'b1;
                        reserve_data_next[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] = bank_read_data[selected_bank];
                        reserve_num_next[lane] = _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(
                            int'(bank_response_row[selected_bank])*STRUCT_IST_BANKS+selected_bank);
                    end
                    response_start_next = BANK_WIDTH'((selected_bank+1) % STRUCT_IST_BANKS);
                end
            end
        end

        for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
            bank_response_valid_next[b] = bank_response_valid[b] && !bank_take[b];
            // Reserve the bank response register before launching a synchronous
            // read. Holding its address preserves data during downstream stalls.
            bank_read[b] = reset_n && request_count[b] != 0 && !bank_response_valid_next[b];
            if (bank_read[b]) begin
                bank_read_row[b] = request_row[b][0];
                bank_response_row_next[b] = request_row[b][0];
                bank_response_valid_next[b] = 1'b1;
                request_row_next[b][0] = request_row[b][1];
                request_count_next[b] = request_count[b]-1'b1;
            end
            // PRM pulses accumulate in pending even when the address FIFO is
            // full. queued remains set through SRAM response and RS acceptance.
            if (reset_n && (|pending_pick[b]) && request_count_next[b] < 2) begin
                request_row_next[b][request_count_next[b][0]] = pending_pick_row[b];
                request_count_next[b] = request_count_next[b]+1'b1;
                for (int row = 0; row < BANK_ROWS; row++) begin
                    if (row*STRUCT_IST_BANKS+b < STRUCT_INST_STATE_ENTRIES && pending_pick[b][row]) begin
                        queued_entries_next[row*STRUCT_IST_BANKS+b] = 1'b1;
                        pending_entries_next[row*STRUCT_IST_BANKS+b] = 1'b0;
                    end
                end
                pending_start_next[b] = (pending_pick_row[b] == BANK_ROWS-1) ? '0 : pending_pick_row[b]+1'b1;
            end
        end
        o_rs_ready_inst_valid = {bypass_valid, issue_valid} & {(STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH){reset_n}};
        o_rs_ready_inst_data[STRUCT_IST_ISSUE_WIDTH*_BITWIDTH_EX_INST_WIDTH-1:0] = issue_data;
    end

    // One independent write and one synchronous read per bank. Memory contents
    // have no reset/flush; active/queued/response valid bits own their lifetime.
    // bram_custom is also the SRAM macro replacement boundary in the ASIC flow.
    generate
        for (genvar b = 0; b < STRUCT_IST_BANKS; b++) begin : G_INSTRUCTION_BANK
            bram_custom #(
                .DATA_WIDTH(_BITWIDTH_EX_INST_WIDTH), .ENTRIES(BANK_ROWS)
            ) U_SRAM (
                .clk(clk), .i_write_en(bank_write[b]),
                .i_write_addr(bank_write_row[b]), .i_write_data(bank_write_data[b]),
                .i_read_addr(bank_read_row[b]), .o_read_data(bank_read_data[b])
            );
        end
    endgenerate

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
        .i_read_addr   (raw_prm_entry_all),
        .o_read_data   (check_phyreg_all),
        .i_write_addr  (allocate_alloc_num_out),
        .i_write_en    (allocate_is_entries),
        .i_write_data  (rs_phyregs)
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
