`timescale 1ns/1ps
module physical_register_mapper #(
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

    // Wait Physical Registers Input (IST)
    input  wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)-1:0]                        i_ist_wait_phyreg_valid, 
    input  wire [(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS*(_BITWIDTH_READY_PRM) )-1:0] i_ist_wait_phyreg_data,
        
    // Broadcast Done phyreg Input (WBC)
    input  wire [STRUCT_EX_OUT_RESULT_SUM-1:0]                                         i_wbc_done_phyreg_valid,
    input  wire [(STRUCT_EX_OUT_RESULT_SUM *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]          i_wbc_done_phyreg_data,

    // Unallocate Retired Registers Input (FCL)
    input  wire [STRUCT_UNALLOCATE_PHYREG-1:0]                                         i_fcl_unallocate_phyreg_valid,
    input  wire [(STRUCT_UNALLOCATE_PHYREG *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]          i_fcl_unallocate_phyreg_data,

    // Allocate Physical Registers Output (NEL)
    output wire [STRUCT_DECODE_NEW_INST-1:0]                                           o_nel_phyreg_valid,
    input  wire [STRUCT_DECODE_NEW_INST-1:0]                                           i_nel_phyreg_get,
    output wire [(STRUCT_DECODE_NEW_INST *(_BITWIDTH_STRUCT_PHYREGS) )-1:0]            o_nel_phyreg_data,

    // Ready Physical Registers Output (IST)
    output logic [STRUCT_PRM_ENTRY_UPDATE-1:0]                                         o_ist_ready_phyreg_valid, 
    output logic [(STRUCT_PRM_ENTRY_UPDATE*(_BITWIDTH_READY_PRM) )-1:0]                o_ist_ready_phyreg_data
);

    logic [STRUCT_PHYREGS-1:0] wait_pending [0:STRUCT_INST_STATE_ENTRIES-1];
    logic [STRUCT_PHYREGS-1:0] wait_pending_next [0:STRUCT_INST_STATE_ENTRIES-1];
    logic [STRUCT_PHYREGS-1:0] wait_map [0:STRUCT_INST_STATE_ENTRIES-1];
    logic [STRUCT_PHYREGS-1:0] wait_map_next [0:STRUCT_INST_STATE_ENTRIES-1];
    localparam int MAP_BANKS = (STRUCT_PRM_ENTRY_BUFFER > 0) ? STRUCT_PRM_ENTRY_BUFFER : 1;
    localparam int MAP_CHUNK = (STRUCT_INST_STATE_ENTRIES+MAP_BANKS-1)/MAP_BANKS;
    localparam int MAP_COUNT_WIDTH = $clog2(STRUCT_INST_STATE_ENTRIES+1);
    logic [(_BITWIDTH_STRUCT_PHYREGS*STRUCT_PHYREGS)-1:0] map_addr;
    logic [(MAP_CHUNK*STRUCT_PHYREGS)-1:0] map_read [0:MAP_BANKS-1];
    logic [(MAP_CHUNK*STRUCT_PHYREGS)-1:0] map_write [0:MAP_BANKS-1];
    logic [(MAP_COUNT_WIDTH*STRUCT_PHYREGS)-1:0] map_counter_read, map_counter_write;
    logic [STRUCT_PHYREGS-1:0] new_wait_for_preg;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0] enqueue_valid, enqueue_ready;
    logic [(_BITWIDTH_READY_PRM*STRUCT_PRM_ENTRY_UPDATE)-1:0] enqueue_data;
    integer lane, entry, preg;
    integer wait_entry, wait_preg;
    integer entry_out, preg_out, enqueue_lane;
    logic [STRUCT_UNALLOCATE_PHYREG-1:0] unallocate_ready;

    allocator #(
        .ENTRIES(STRUCT_PHYREGS-1), .START_VALUE(1),
        .ALLOCATE_CHANNEL(STRUCT_DECODE_NEW_INST),
        .UNALLOCATE_CHANNEL(STRUCT_UNALLOCATE_PHYREG)
    ) U_PRM_PHYREG_ALLOCATOR (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_unallocate(i_fcl_unallocate_phyreg_valid),
        .o_unallocate_ready(unallocate_ready),
        .i_unallocate_data(i_fcl_unallocate_phyreg_data),
        .i_allocate(i_nel_phyreg_get), .o_allocate_valid(o_nel_phyreg_valid),
        .o_allocate_data(o_nel_phyreg_data)
    );

    // Gen2's mapping instances hold consecutive slices of the IST bitmap for
    // every physical register. Slicing keeps all waiters, including more than
    // STRUCT_PRM_ENTRY_BUFFER waiters on the same physical register.
    for (genvar physical = 0; physical < STRUCT_PHYREGS; physical++) begin : GEN_MAP_ADDRESS
        assign map_addr[physical*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS] =
            _BITWIDTH_STRUCT_PHYREGS'(physical);
        for (genvar state_entry = 0; state_entry < STRUCT_INST_STATE_ENTRIES; state_entry++) begin : GEN_MAP_BIT
            assign wait_map[state_entry][physical] =
                map_read[state_entry/MAP_CHUNK][physical*MAP_CHUNK + state_entry%MAP_CHUNK];
        end
    end

    regfile #(
        .DATA_WIDTH(MAP_COUNT_WIDTH), .ENTRIES(STRUCT_PHYREGS),
        .READ_CHANNEL(STRUCT_PHYREGS), .WRITE_CHANNEL(STRUCT_PHYREGS)
    ) U_PRM_MAPPING_COUNTER (
        .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
        .i_read_addr(map_addr), .o_read_data(map_counter_read),
        .i_write_addr(map_addr), .i_write_en({STRUCT_PHYREGS{1'b1}}),
        .i_write_data(map_counter_write)
    );

    for (genvar bank = 0; bank < MAP_BANKS; bank++) begin : GEN_PRM_MAP
        for (genvar physical = 0; physical < STRUCT_PHYREGS; physical++) begin : GEN_WRITE_SLICE
            for (genvar bit_idx = 0; bit_idx < MAP_CHUNK; bit_idx++) begin : GEN_WRITE_BIT
                if (bank*MAP_CHUNK+bit_idx < STRUCT_INST_STATE_ENTRIES) begin
                    assign map_write[bank][physical*MAP_CHUNK+bit_idx] =
                        wait_map_next[bank*MAP_CHUNK+bit_idx][physical];
                end
                else begin
                    assign map_write[bank][physical*MAP_CHUNK+bit_idx] = 1'b0;
                end
            end
        end
        regfile #(
            .DATA_WIDTH(MAP_CHUNK), .ENTRIES(STRUCT_PHYREGS),
            .READ_CHANNEL(STRUCT_PHYREGS), .WRITE_CHANNEL(STRUCT_PHYREGS)
        ) U_PRM_IST_MAP (
            .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
            .i_read_addr(map_addr), .o_read_data(map_read[bank]),
            .i_write_addr(map_addr), .i_write_en({STRUCT_PHYREGS{1'b1}}),
            .i_write_data(map_write[bank])
        );
    end

    // Each output lane keeps the Gen2 FIFO instance. Completion events enter
    // at the same edge that used to set wait_pending, so IST sees them at the
    // same following cycle. The bitmap holds any excess until a FIFO lane is free.
    for (genvar output_lane = 0; output_lane < STRUCT_PRM_ENTRY_UPDATE; output_lane++) begin : GEN_PRM_OUTPUT
        fifo_multichan #(
            .DATA_WIDTH(_BITWIDTH_READY_PRM), .READ_CHANNEL(1),
            .WRITE_CHANNEL(1), .MIN_FIFO_ENTRY(2)
        ) U_PRM_OUTPUT_FIFO (
            .clk(clk), .reset_n(reset_n), .i_flush(1'b0),
            .i_push(enqueue_valid[output_lane]),
            .o_push_ready(enqueue_ready[output_lane]),
            .i_push_data(enqueue_data[output_lane*_BITWIDTH_READY_PRM +: _BITWIDTH_READY_PRM]),
            .i_pop(o_ist_ready_phyreg_valid[output_lane]),
            .o_pop_valid(o_ist_ready_phyreg_valid[output_lane]),
            .o_pop_data(o_ist_ready_phyreg_data[output_lane*_BITWIDTH_READY_PRM +: _BITWIDTH_READY_PRM])
        );
    end

    always_comb begin
        for (entry = 0; entry < STRUCT_INST_STATE_ENTRIES; entry++) begin
            wait_pending_next[entry] = wait_pending[entry];
            wait_map_next[entry] = wait_map[entry];
        end
        new_wait_for_preg = '0;
        enqueue_valid = '0;
        enqueue_data = '0;
        enqueue_lane = 0;

        // Record all outstanding (physical register, IST entry) dependencies.
        for (lane = 0; lane < STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS; lane++) begin
            wait_preg = int'(i_ist_wait_phyreg_data[lane*_BITWIDTH_READY_PRM +: _BITWIDTH_STRUCT_PHYREGS]);
            wait_entry = int'(i_ist_wait_phyreg_data[lane*_BITWIDTH_READY_PRM + _BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES]);
            if (i_ist_wait_phyreg_valid[lane] && wait_preg < STRUCT_PHYREGS && wait_entry < STRUCT_INST_STATE_ENTRIES) begin
                wait_map_next[wait_entry][wait_preg] = 1'b1;
                new_wait_for_preg[wait_preg] = 1'b1;
            end
        end

        // Completion events turn waiters into pending update messages.
        for (lane = 0; lane < STRUCT_EX_OUT_RESULT_SUM; lane++) begin
            preg = int'(i_wbc_done_phyreg_data[lane*_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_PHYREGS]);
            if (i_wbc_done_phyreg_valid[lane] && preg < STRUCT_PHYREGS &&
                (map_counter_read[preg*MAP_COUNT_WIDTH +: MAP_COUNT_WIDTH] != 0 ||
                 new_wait_for_preg[preg])) begin
                for (entry = 0; entry < STRUCT_INST_STATE_ENTRIES; entry++) begin
                    if (wait_map_next[entry][preg]) wait_pending_next[entry][preg] = 1'b1;
                end
            end
        end

        for (entry_out = 0; entry_out < STRUCT_INST_STATE_ENTRIES; entry_out++) begin
            for (preg_out = 1; preg_out < STRUCT_PHYREGS; preg_out++) begin
                if (wait_pending_next[entry_out][preg_out] &&
                    enqueue_lane < STRUCT_PRM_ENTRY_UPDATE && enqueue_ready[enqueue_lane]) begin
                    enqueue_valid[enqueue_lane] = 1'b1;
                    enqueue_data[enqueue_lane*_BITWIDTH_READY_PRM +: _BITWIDTH_READY_PRM] =
                        _BITWIDTH_READY_PRM'((entry_out << _BITWIDTH_STRUCT_PHYREGS) | preg_out);
                    wait_pending_next[entry_out][preg_out] = 1'b0;
                    wait_map_next[entry_out][preg_out] = 1'b0;
                    enqueue_lane++;
                end
            end
        end
        map_counter_write = '0;
        for (preg = 0; preg < STRUCT_PHYREGS; preg++) begin
            for (entry = 0; entry < STRUCT_INST_STATE_ENTRIES; entry++) begin
                if (wait_map_next[entry][preg])
                    map_counter_write[preg*MAP_COUNT_WIDTH +: MAP_COUNT_WIDTH] =
                        map_counter_write[preg*MAP_COUNT_WIDTH +: MAP_COUNT_WIDTH] + 1'b1;
            end
        end
    end

    for (genvar idx = 0; idx < STRUCT_INST_STATE_ENTRIES; idx++) begin : GEN_WAIT_ENTRY
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                wait_pending[idx] <= '0;
            end
            else begin
                wait_pending[idx] <= wait_pending_next[idx];
            end
        end
    end

endmodule
