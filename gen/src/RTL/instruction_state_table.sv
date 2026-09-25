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
    output logic [((STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)*_BITWIDTH_EX_INST_WIDTH)-1:0]     o_rs_ready_inst_data,
    input  logic [(STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE)-1:0]                              i_rs_ready_inst_get,

    // Wait Physical Registers Output (PRM)
    output logic [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]                                      o_prm_wait_phyreg_valid,
    output logic [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS*(_BITWIDTH_READY_PRM) )-1:0]               o_prm_wait_phyreg_data
);

    localparam int NEW_UPDATE_WIDTH = STRUCT_DECODE_NEW_INST + STRUCT_PRM_ENTRY_UPDATE;
    localparam int STARTBIT_RS_PART = _BITWIDTH_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH
                                    + _BITWIDTH_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH
                                    + IS_INST_IMM + _BITWIDTH_STRUCT_PHYREGS;
    localparam int STARTBIT_READY_PART = STARTBIT_RS_PART
                                       + (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS);
    localparam int STARTBIT_EX_SOURCE = _BITWIDTH_STRUCT_FLOW_WINDOWS + IS_INST_PC_BITWIDTH
                                      + _BITWIDTH_STRUCT_EX_PATH + EX_INST_MICROOP_BITWIDTH
                                      + IS_INST_IMM + _BITWIDTH_STRUCT_PHYREGS;

    logic [STRUCT_INST_STATE_ENTRIES-1:0] entry_busy;
    logic [IS_INST_OPERANDS-1:0] entry_ready [0:STRUCT_INST_STATE_ENTRIES-1];
    logic [IS_INST_OPERANDS-1:0] entry_ready_next [0:STRUCT_INST_STATE_ENTRIES-1];
    logic [(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)-1:0] entry_source [0:STRUCT_INST_STATE_ENTRIES-1];
    logic [_BITWIDTH_EX_INST_WIDTH-1:0] entry_data [0:STRUCT_INST_STATE_ENTRIES-1];
    logic [(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*STRUCT_INST_STATE_ENTRIES)-1:0] table_read_addr;
    logic [(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS*STRUCT_INST_STATE_ENTRIES)-1:0] source_read_data;
    logic [(_BITWIDTH_EX_INST_WIDTH*STRUCT_INST_STATE_ENTRIES)-1:0] data_read_data;
    logic [(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS*STRUCT_DECODE_NEW_INST)-1:0] source_write_data;
    logic [(_BITWIDTH_EX_INST_WIDTH*STRUCT_DECODE_NEW_INST)-1:0] data_write_data;
    logic [(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*NEW_UPDATE_WIDTH)-1:0] ready_write_addr;
    logic [NEW_UPDATE_WIDTH-1:0] ready_write_en;
    logic [NEW_UPDATE_WIDTH-1:0] ready_write_data [0:IS_INST_OPERANDS-1];
    logic [STRUCT_INST_STATE_ENTRIES-1:0] ready_read_data [0:IS_INST_OPERANDS-1];
    logic [STRUCT_DECODE_NEW_INST-1:0] allocate_fire;
    logic [STRUCT_DECODE_NEW_INST-1:0] allocate_valid;
    logic [(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*STRUCT_DECODE_NEW_INST)-1:0] allocate_data;
    logic [NEW_UPDATE_WIDTH-1:0] free_valid;
    logic [(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*NEW_UPDATE_WIDTH)-1:0] free_data;
    logic [NEW_UPDATE_WIDTH-1:0] output_entry_valid;
    logic [(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*NEW_UPDATE_WIDTH)-1:0] output_entry_id;
    logic [NEW_UPDATE_WIDTH-1:0] output_lane_used;
    integer alloc_lane, update_lane, entry_idx, operand_idx, output_lane, candidate_idx;
    integer update_entry, update_preg;
    logic [IS_INST_OPERANDS-1:0] ready_after_update;

    assign allocate_fire = i_nel_new_inst_valid & o_nel_new_inst_get;
    for (genvar lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin : GEN_TABLE_WRITE
        assign source_write_data[lane*(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS) +:
                                 (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)] =
            i_nel_new_inst_data[lane*_BITWIDTH_INTERNAL_INST_WIDTH + STARTBIT_RS_PART +:
                                (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)];
        assign data_write_data[lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] =
            i_nel_new_inst_data[lane*_BITWIDTH_INTERNAL_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH];
    end
    for (genvar entry = 0; entry < STRUCT_INST_STATE_ENTRIES; entry++) begin : GEN_TABLE_READ
        assign table_read_addr[entry*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                               _BITWIDTH_STRUCT_INST_STATE_ENTRIES] =
            _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(entry);
        assign entry_source[entry] = source_read_data[entry*(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS) +:
                                                      (_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)];
        assign entry_data[entry] = data_read_data[entry*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH];
        for (genvar operand = 0; operand < IS_INST_OPERANDS; operand++) begin : GEN_READY_READ
            assign entry_ready[entry][operand] = ready_read_data[operand][entry];
        end
    end

    regfile #(
        .DATA_WIDTH(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS),
        .ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .READ_CHANNEL(STRUCT_INST_STATE_ENTRIES),
        .WRITE_CHANNEL(STRUCT_DECODE_NEW_INST)
    ) U_IST_SOURCE_TABLE (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_read_addr(table_read_addr), .o_read_data(source_read_data),
        .i_write_addr(allocate_data), .i_write_en(allocate_fire),
        .i_write_data(source_write_data)
    );

    regfile #(
        .DATA_WIDTH(_BITWIDTH_EX_INST_WIDTH),
        .ENTRIES(STRUCT_INST_STATE_ENTRIES),
        .READ_CHANNEL(STRUCT_INST_STATE_ENTRIES),
        .WRITE_CHANNEL(STRUCT_DECODE_NEW_INST)
    ) U_IST_ENTRY_TABLE (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_read_addr(table_read_addr), .o_read_data(data_read_data),
        .i_write_addr(allocate_data), .i_write_en(allocate_fire),
        .i_write_data(data_write_data)
    );

    always_comb begin
        ready_write_addr = '0;
        ready_write_en = '0;
        for (int lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
            ready_write_addr[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                             _BITWIDTH_STRUCT_INST_STATE_ENTRIES] =
                allocate_data[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                              _BITWIDTH_STRUCT_INST_STATE_ENTRIES];
            ready_write_en[lane] = allocate_fire[lane];
        end
        for (int lane = 0; lane < STRUCT_PRM_ENTRY_UPDATE; lane++) begin
            ready_write_addr[(STRUCT_DECODE_NEW_INST+lane)*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                             _BITWIDTH_STRUCT_INST_STATE_ENTRIES] =
                i_prm_ready_phyreg_data[lane*_BITWIDTH_READY_PRM + _BITWIDTH_STRUCT_PHYREGS +:
                                         _BITWIDTH_STRUCT_INST_STATE_ENTRIES];
            ready_write_en[STRUCT_DECODE_NEW_INST+lane] = i_prm_ready_phyreg_valid[lane] &&
                int'(ready_write_addr[(STRUCT_DECODE_NEW_INST+lane)*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                                      _BITWIDTH_STRUCT_INST_STATE_ENTRIES]) < STRUCT_INST_STATE_ENTRIES;
        end
        for (int entry = 0; entry < STRUCT_INST_STATE_ENTRIES; entry++) begin
            entry_ready_next[entry] = entry_ready[entry];
            for (int lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
                if (allocate_fire[lane] &&
                    int'(allocate_data[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                                       _BITWIDTH_STRUCT_INST_STATE_ENTRIES]) == entry)
                    entry_ready_next[entry] =
                        i_nel_new_inst_data[lane*_BITWIDTH_INTERNAL_INST_WIDTH + STARTBIT_READY_PART +:
                                            IS_INST_OPERANDS];
            end
            for (int lane = 0; lane < STRUCT_PRM_ENTRY_UPDATE; lane++) begin
                if (ready_write_en[STRUCT_DECODE_NEW_INST+lane] &&
                    int'(ready_write_addr[(STRUCT_DECODE_NEW_INST+lane)*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                                          _BITWIDTH_STRUCT_INST_STATE_ENTRIES]) == entry) begin
                    for (int operand = 0; operand < IS_INST_OPERANDS; operand++) begin
                        if (entry_source[entry][operand*_BITWIDTH_STRUCT_PHYREGS +:
                                                _BITWIDTH_STRUCT_PHYREGS] ==
                            i_prm_ready_phyreg_data[lane*_BITWIDTH_READY_PRM +:
                                                     _BITWIDTH_STRUCT_PHYREGS])
                            entry_ready_next[entry][operand] = 1'b1;
                    end
                end
            end
        end
        for (int operand = 0; operand < IS_INST_OPERANDS; operand++) begin
            ready_write_data[operand] = '0;
            for (int lane = 0; lane < NEW_UPDATE_WIDTH; lane++) begin
                for (int entry = 0; entry < STRUCT_INST_STATE_ENTRIES; entry++) begin
                    if (int'(ready_write_addr[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +:
                                               _BITWIDTH_STRUCT_INST_STATE_ENTRIES]) == entry)
                        ready_write_data[operand][lane] = entry_ready_next[entry][operand];
                end
            end
        end
    end

    for (genvar operand = 0; operand < IS_INST_OPERANDS; operand++) begin : GEN_IST_READY_FLAGS
        regfile #(
            .DATA_WIDTH(1), .ENTRIES(STRUCT_INST_STATE_ENTRIES),
            .READ_CHANNEL(STRUCT_INST_STATE_ENTRIES), .WRITE_CHANNEL(NEW_UPDATE_WIDTH)
        ) U_IST_READY_FLAGS_TABLE (
            .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
            .i_read_addr(table_read_addr), .o_read_data(ready_read_data[operand]),
            .i_write_addr(ready_write_addr), .i_write_en(ready_write_en),
            .i_write_data(ready_write_data[operand])
        );
    end

    always_comb begin
        free_valid = '0;
        free_data = '0;
        o_nel_new_inst_get = '0;
        o_rs_ready_inst_valid = '0;
        o_rs_ready_inst_data = '0;
        o_prm_wait_phyreg_valid = '0;
        o_prm_wait_phyreg_data = '0;
        output_entry_valid = '0;
        output_entry_id = '0;
        output_lane_used = '0;

        for (alloc_lane = 0; alloc_lane < STRUCT_DECODE_NEW_INST; alloc_lane++) begin
            o_nel_new_inst_get[alloc_lane] = allocate_valid[alloc_lane];
        end

        // Preserve the decode-lane order when allocating IST entries.
        for (alloc_lane = 0; alloc_lane < STRUCT_DECODE_NEW_INST; alloc_lane++) begin
            if (i_nel_new_inst_valid[alloc_lane] && allocate_valid[alloc_lane]) begin
                for (operand_idx = 0; operand_idx < IS_INST_OPERANDS; operand_idx++) begin
                    if (!i_nel_new_inst_data[alloc_lane*_BITWIDTH_INTERNAL_INST_WIDTH + STARTBIT_READY_PART + operand_idx]) begin
                        o_prm_wait_phyreg_valid[alloc_lane*IS_INST_OPERANDS+operand_idx] = 1'b1;
                        o_prm_wait_phyreg_data[(alloc_lane*IS_INST_OPERANDS+operand_idx)*_BITWIDTH_READY_PRM +: _BITWIDTH_READY_PRM] = {
                            allocate_data[alloc_lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES],
                            i_nel_new_inst_data[alloc_lane*_BITWIDTH_INTERNAL_INST_WIDTH + STARTBIT_RS_PART + operand_idx*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS]
                        };
                    end
                end
            end
        end

        // Select ready entries in age order. Entries remain resident until RS accepts them.
        output_lane = 0;
        for (entry_idx = 0; entry_idx < STRUCT_INST_STATE_ENTRIES; entry_idx++) begin
            ready_after_update = entry_ready[entry_idx];
            for (update_lane = 0; update_lane < STRUCT_PRM_ENTRY_UPDATE; update_lane++) begin
                update_entry = int'(i_prm_ready_phyreg_data[update_lane*_BITWIDTH_READY_PRM + _BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES]);
                update_preg = int'(i_prm_ready_phyreg_data[update_lane*_BITWIDTH_READY_PRM +: _BITWIDTH_STRUCT_PHYREGS]);
                if (i_prm_ready_phyreg_valid[update_lane] && update_entry == entry_idx) begin
                    for (operand_idx = 0; operand_idx < IS_INST_OPERANDS; operand_idx++) begin
                        if (int'(entry_source[entry_idx][operand_idx*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS]) == update_preg)
                            ready_after_update[operand_idx] = 1'b1;
                    end
                end
            end
            if (entry_busy[entry_idx] && (&ready_after_update) && output_lane < NEW_UPDATE_WIDTH) begin
                output_entry_valid[output_lane] = 1'b1;
                output_entry_id[output_lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] = _BITWIDTH_STRUCT_INST_STATE_ENTRIES'(entry_idx);
                o_rs_ready_inst_valid[output_lane] = 1'b1;
                o_rs_ready_inst_data[output_lane*_BITWIDTH_EX_INST_WIDTH +: _BITWIDTH_EX_INST_WIDTH] = entry_data[entry_idx];
                output_lane++;
            end
        end

        for (output_lane = 0; output_lane < NEW_UPDATE_WIDTH; output_lane++) begin
            if (output_entry_valid[output_lane] && i_rs_ready_inst_get[output_lane]) begin
                free_valid[output_lane] = 1'b1;
                free_data[output_lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] =
                    output_entry_id[output_lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES];
            end
        end
    end

    allocator #(
        .ENTRIES(STRUCT_INST_STATE_ENTRIES), .START_VALUE(0),
        .ALLOCATE_CHANNEL(STRUCT_DECODE_NEW_INST), .UNALLOCATE_CHANNEL(NEW_UPDATE_WIDTH)
    ) U_IST_ENTRY_ALLOCATOR (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_unallocate(free_valid), .o_unallocate_ready(), .i_unallocate_data(free_data),
        .i_allocate(i_nel_new_inst_valid & o_nel_new_inst_get),
        .o_allocate_valid(allocate_valid), .o_allocate_data(allocate_data)
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            entry_busy <= '0;
        end
        else begin
            for (int lane = 0; lane < STRUCT_DECODE_NEW_INST; lane++) begin
                if (i_nel_new_inst_valid[lane] && o_nel_new_inst_get[lane]) begin
                    entry_busy[allocate_data[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES]] <= 1'b1;
                end
            end

            for (int lane = 0; lane < NEW_UPDATE_WIDTH; lane++) begin
                if (free_valid[lane])
                    entry_busy[output_entry_id[lane*_BITWIDTH_STRUCT_INST_STATE_ENTRIES +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES]] <= 1'b0;
            end
        end
    end

endmodule
