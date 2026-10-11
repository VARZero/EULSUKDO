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
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]                       ready_check_phyreg_target;

    logic                                                     nel_accept_enable;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                        prm_update_write;
    logic [STRUCT_INST_STATE_ENTRIES-1:0]                     active_entries, active_entries_next;
    logic [STRUCT_INST_STATE_ENTRIES-1:0]                     pending_entries, pending_entries_next;
    localparam int BANK_BITS = $clog2(STRUCT_IST_BANKS);
    localparam int BANK_WIDTH = (BANK_BITS > 0) ? BANK_BITS : 1;
    localparam int BANK_ROWS = (STRUCT_INST_STATE_ENTRIES+STRUCT_IST_BANKS-1)/STRUCT_IST_BANKS;
    localparam int ROW_WIDTH = (BANK_ROWS > 1) ? $clog2(BANK_ROWS) : 1;
    localparam int ALLOC_WIDTH = STRUCT_DECODE_NEW_INST*(_BITWIDTH_STRUCT_INST_STATE_ENTRIES+1);

    logic [STRUCT_INST_STATE_ENTRIES-1:0] queued_entries, queued_entries_next;
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
    integer idx_internal_inst, idx_rs, idx_update, idx_entry;
    integer selected_bank, candidate_bank, selected_row, candidate_row, entry_num;

    initial begin
        if (STRUCT_IST_ISSUE_WIDTH < 1 || STRUCT_IST_BANKS < STRUCT_DECODE_NEW_INST ||
            (STRUCT_IST_BANKS & (STRUCT_IST_BANKS-1)) != 0 || STRUCT_INST_STATE_ENTRIES < STRUCT_DECODE_NEW_INST)
            $fatal(1, "IST requires positive issue width, power-of-two banks >= decode, entries >= decode");
    end

    // Offers depend only on registered occupancy, not on NEL Valid/data/Get.
    // Prefer banks with more free rows; rotate equal-capacity choices. This
    // balances partial/sparse allocations and masks padding in the final row.
    function automatic logic [ALLOC_WIDTH-1:0] allocation_offers(
        input logic [STRUCT_INST_STATE_ENTRIES-1:0] active,
        input logic [BANK_WIDTH-1:0] start_bank
    );
        int free_count [STRUCT_IST_BANKS];
        int free_row [STRUCT_IST_BANKS];
        bit used [STRUCT_IST_BANKS];
        int chosen, candidate;
        logic [ALLOC_WIDTH-1:0] result;
        result = '0;
        for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
            free_count[b] = 0; free_row[b] = 0; used[b] = 0;
            for (int r = BANK_ROWS-1; r >= 0; r--) begin
                if ((r*STRUCT_IST_BANKS+b) < STRUCT_INST_STATE_ENTRIES) begin
                    if (!active[r*STRUCT_IST_BANKS+b]) begin
                        free_count[b]++; free_row[b] = r;
                    end
                end
            end
        end
        for (int lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
            chosen = -1;
            for (int offset = 0; offset < STRUCT_IST_BANKS; offset++) begin
                candidate = (int'(start_bank)+offset) % STRUCT_IST_BANKS;
                if (!used[candidate] && free_count[candidate] != 0) begin
                    if (chosen < 0) chosen = candidate;
                    else if (free_count[candidate] > free_count[chosen]) chosen = candidate;
                end
            end
            if (chosen >= 0) begin
                used[chosen] = 1;
                result[_BITWIDTH_ALLOC_IST_NUM+lane] = 1;
                result[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] =
                    _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(free_row[chosen]*STRUCT_IST_BANKS+chosen);
            end
        end
        return result;
    endfunction
    assign {allocate_valid, allocate_alloc_num_out} = allocation_offers(active_entries, alloc_start);

    // Admission reserves a complete bundle in the ready bypass register. Keeping
    // this wiring outside the NEL-consuming block also makes that independence
    // visible to simulators when NEL gates its Valid with our Get.
    assign nel_accept_enable = reset_n &&
        (&allocate_valid) && !(|(bypass_valid & ~i_rs_ready_inst_get[STRUCT_IST_ISSUE_WIDTH +: STRUCT_DECODE_NEW_INST]));
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
            active_entries <= '0; pending_entries <= '0; queued_entries <= '0;
            bypass_valid <= '0; bypass_data <= '0;
            alloc_start <= '0; response_start <= '0;
            bank_response_valid <= '0;
            issue_valid <= '0; issue_data <= '0;
            for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
                bank_response_row[b] <= '0; request_count[b] <= '0; pending_start[b] <= '0;
                for (int q = 0; q < 2; q++) request_row[b][q] <= '0;
            end
            for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) issue_num[lane] <= '0;
        end
        else begin
            active_entries <= active_entries_next; pending_entries <= pending_entries_next;
            queued_entries <= queued_entries_next;
            bypass_valid <= bypass_valid_next; bypass_data <= bypass_data_next;
            alloc_start <= alloc_start_next; response_start <= response_start_next;
            bank_response_valid <= bank_response_valid_next;
            issue_valid <= issue_valid_next; issue_data <= issue_data_next;
            for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
                bank_response_row[b] <= bank_response_row_next[b];
                request_count[b] <= request_count_next[b]; pending_start[b] <= pending_start_next[b];
                for (int q = 0; q < 2; q++) request_row[b][q] <= request_row_next[b][q];
            end
            for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) issue_num[lane] <= issue_num_next[lane];
        end
    end

    always_comb begin
        allocate_is_entries = '0; ready_is_entries = '0;
        active_entries_next  = active_entries;
        pending_entries_next = pending_entries;
        prm_update_write     = '0;
        ready_check_section  = '0;
        ready_check_phyreg_target = '0;
        bypass_valid_next = bypass_valid & ~i_rs_ready_inst_get[STRUCT_IST_ISSUE_WIDTH +: STRUCT_DECODE_NEW_INST];
        bypass_data_next = bypass_data;
        queued_entries_next = queued_entries;
        alloc_start_next = alloc_start; response_start_next = response_start;
        bank_write = '0; bank_read = '0; bank_take = '0;
        bank_response_valid_next = bank_response_valid;
        issue_valid_next = issue_valid & ~i_rs_ready_inst_get[STRUCT_IST_ISSUE_WIDTH-1:0];
        issue_data_next = issue_data;
        selected_bank = -1; candidate_bank = 0; selected_row = -1; candidate_row = 0; entry_num = 0;
        for (int b = 0; b < STRUCT_IST_BANKS; b++) begin
            bank_write_row[b] = '0; bank_write_data[b] = '0;
            bank_read_row[b] = bank_response_row[b];
            bank_response_row_next[b] = bank_response_row[b];
            request_count_next[b] = request_count[b]; pending_start_next[b] = pending_start[b];
            for (int q = 0; q < 2; q++) request_row_next[b][q] = request_row[b][q];
        end
        for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) issue_num_next[lane] = issue_num[lane];

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
                bypass_valid_next[idx_internal_inst] = 1'b1;
                bypass_data_next[idx_internal_inst*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] = target_ist_entry[idx_internal_inst];
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
            if (prm_update_write[idx_internal_inst] && (&ready_check_section) &&
                !queued_entries[prm_update_istnum[idx_internal_inst]]) begin
                pending_entries_next[prm_update_istnum[idx_internal_inst]] = 1'b1;
            end
        end

        // Each output lane is an elastic holding register. Partial Get only
        // replaces accepted lanes; bank arbitration is round-robin and narrow.
        for (int lane = 0; lane < STRUCT_IST_ISSUE_WIDTH; lane++) begin
            if (issue_valid[lane] && i_rs_ready_inst_get[lane]) begin
                active_entries_next[issue_num[lane]] = 1'b0;
                pending_entries_next[issue_num[lane]] = 1'b0;
                queued_entries_next[issue_num[lane]] = 1'b0;
            end
            if (!issue_valid_next[lane]) begin
                selected_bank = -1;
                for (int offset = 0; offset < STRUCT_IST_BANKS; offset++) begin
                    candidate_bank = (int'(response_start)+offset) % STRUCT_IST_BANKS;
                    if (selected_bank < 0 && bank_response_valid[candidate_bank] && !bank_take[candidate_bank])
                        selected_bank = candidate_bank;
                end
                if (selected_bank >= 0) begin
                    bank_take[selected_bank] = 1'b1;
                    issue_valid_next[lane] = 1'b1;
                    issue_data_next[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] = bank_read_data[selected_bank];
                    issue_num_next[lane] = _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(
                        int'(bank_response_row[selected_bank])*STRUCT_IST_BANKS+selected_bank);
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
            selected_row = -1;
            for (int offset = 0; offset < BANK_ROWS; offset++) begin
                candidate_row = int'(pending_start[b])+offset;
                if (candidate_row >= BANK_ROWS) candidate_row = candidate_row-BANK_ROWS;
                entry_num = candidate_row*STRUCT_IST_BANKS+b;
                if (entry_num < STRUCT_INST_STATE_ENTRIES) begin
                    if (selected_row < 0 && pending_entries[entry_num] && !queued_entries[entry_num])
                        selected_row = candidate_row;
                end
            end
            if (reset_n && selected_row >= 0 && request_count_next[b] < 2) begin
                request_row_next[b][request_count_next[b][0]] = ROW_WIDTH'(selected_row);
                request_count_next[b] = request_count_next[b]+1'b1;
                queued_entries_next[selected_row*STRUCT_IST_BANKS+b] = 1'b1;
                pending_entries_next[selected_row*STRUCT_IST_BANKS+b] = 1'b0;
                pending_start_next[b] = (selected_row == BANK_ROWS-1) ? '0 : ROW_WIDTH'(selected_row+1);
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
        .i_read_addr   (prm_update_istnum_all),
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
