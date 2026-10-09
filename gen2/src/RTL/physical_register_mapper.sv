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
    parameter int STRUCT_PRM_OUTPUT_FIFO_DEPTH          = 64,
    parameter int STRUCT_PRM_INPUT_BUFFER_DEPTH         = 2,

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
    output wire [STRUCT_PRM_ENTRY_UPDATE-1:0]                                          o_ist_ready_phyreg_valid, 
    output logic [(STRUCT_PRM_ENTRY_UPDATE*(_BITWIDTH_READY_PRM) )-1:0]                o_ist_ready_phyreg_data
);

    // Parameters require positive channel/buffer sizes and STRUCT_PHYREGS >= 2.
    localparam int WAIT_INPUTS                     = STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS;
    // One blocked bundle + one already-renamed NEL Stage 2 bundle.
    // Deeper upstream pipelines require a larger buffer / reservation policy.
    localparam int INPUT_BUFFER_ENTRIES            = (STRUCT_PRM_INPUT_BUFFER_DEPTH < 2)? 2 : STRUCT_PRM_INPUT_BUFFER_DEPTH;
    localparam int _BITWIDTH_INPUT_BUNDLE           = WAIT_INPUTS*(_BITWIDTH_READY_PRM+1);
    localparam int _BITWIDTH_INPUT_BUFFER_ADDR      = $clog2(INPUT_BUFFER_ENTRIES);
    localparam int _BITWIDTH_INPUT_BUFFER_COUNT     = $clog2(INPUT_BUFFER_ENTRIES+1);
    localparam int COUNTER_CHANNELS                = WAIT_INPUTS+1;
    localparam int OUTPUT_PUSH_CHANNELS            = STRUCT_PRM_ENTRY_BUFFER+WAIT_INPUTS;
    localparam int OUTPUT_FIFO_ENTRIES             = (STRUCT_PRM_OUTPUT_FIFO_DEPTH < OUTPUT_PUSH_CHANNELS)?
                                                        OUTPUT_PUSH_CHANNELS : STRUCT_PRM_OUTPUT_FIFO_DEPTH;
    localparam int _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER = $clog2(STRUCT_PRM_ENTRY_BUFFER+1);
    localparam int _BITWIDTH_OUTPUT_FIFO_ADDR       = (OUTPUT_FIFO_ENTRIES > 1)? $clog2(OUTPUT_FIFO_ENTRIES) : 1;
    localparam int _BITWIDTH_OUTPUT_FIFO_COUNT      = $clog2(OUTPUT_FIFO_ENTRIES+1);
    localparam int _BITWIDTH_WAIT_COUNT             = $clog2(STRUCT_INST_STATE_ENTRIES*IS_INST_OPERANDS+WAIT_INPUTS+1);

    logic [_BITWIDTH_READY_PRM-1:0]                 wait_input_list       [0:WAIT_INPUTS-1];
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]            wait_input_phyreg     [0:WAIT_INPUTS-1];
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] wait_input_istentry   [0:WAIT_INPUTS-1];
    logic [WAIT_INPUTS-1:0]                         wait_input_valid;
    logic [WAIT_INPUTS-1:0]                         wait_ready_valid;
    logic [STRUCT_PHYREGS-1:0]                      wait_map_list         [0:WAIT_INPUTS-1];
    logic [WAIT_INPUTS-1:0]                         wait_map_phyreg       [0:STRUCT_PHYREGS-1];
    integer                                        wait_prefix_count     [0:WAIT_INPUTS-1];
    logic [WAIT_INPUTS-1:0]                         wait_suffix_valid;

    // Capture the complete IST input (Valid + Data) before mapping it.
    // If any unfinished PHYREG would overflow, retain the entire head bundle.
    // New physical-register offers stop; WBC and already-renamed IST inputs continue.
    logic [_BITWIDTH_INPUT_BUFFER_ADDR-1:0]        input_read_ptr, input_read_ptr_next;
    logic [_BITWIDTH_INPUT_BUFFER_ADDR-1:0]        input_write_ptr, input_write_ptr_next;
    logic [_BITWIDTH_INPUT_BUFFER_COUNT-1:0]       input_count, input_count_next;
    wire  [_BITWIDTH_INPUT_BUNDLE-1:0]             input_buffer_read_data;
    wire  [_BITWIDTH_INPUT_BUNDLE-1:0]             input_buffer_write_data;
    logic                                         input_push, input_fire, input_stall;
    logic                                         input_map_fit;
    integer                                       input_ready_count;
    // Deduplicate for lifetime accounting at capture; keep the raw bundle in RAM.
    logic [WAIT_INPUTS-1:0]                        recv_input_valid;
    logic [_BITWIDTH_READY_PRM-1:0]                recv_input_list       [0:WAIT_INPUTS-1];
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]           recv_input_phyreg     [0:WAIT_INPUTS-1];

    // Ready remains set until allocation of a new lifetime, so a one-cycle WBC
    // pulse is not lost while the output FIFO is full or an input bundle is held.
    logic [STRUCT_PHYREGS-1:0]                      phyreg_ready, phyreg_ready_next;
    logic [STRUCT_PHYREGS-1:0]                      mapping_active, mapping_active_next;
    logic [STRUCT_PHYREGS-1:0]                      retired_pending, retired_pending_next;
    logic [_BITWIDTH_WAIT_COUNT-1:0]                wait_count            [0:STRUCT_PHYREGS-1];
    logic [_BITWIDTH_WAIT_COUNT-1:0]                wait_count_next       [0:STRUCT_PHYREGS-1];

    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]            drain_start, drain_start_next;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]            drain_phyreg;
    logic                                           drain_valid, drain_fire;

    // Counter port 0 drains a completed row; ports 1..WAIT_INPUTS append requests.
    logic [(COUNTER_CHANNELS*_BITWIDTH_STRUCT_PHYREGS)-1:0] counter_addr;
    logic [(COUNTER_CHANNELS*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER)-1:0] counter_read_data;
    logic [(COUNTER_CHANNELS*_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER)-1:0] counter_write_data;
    logic [COUNTER_CHANNELS-1:0]                    counter_write_valid;
    logic [(WAIT_INPUTS*_BITWIDTH_STRUCT_PHYREGS)-1:0] mapping_write_addr;
    logic [(WAIT_INPUTS*_BITWIDTH_STRUCT_INST_STATE_ENTRIES)-1:0] mapping_write_data;
    logic [WAIT_INPUTS-1:0]                         mapping_write_valid   [0:STRUCT_PRM_ENTRY_BUFFER-1];
    wire  [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] mapping_read_data     [0:STRUCT_PRM_ENTRY_BUFFER-1];

    // A shared FIFO admits a completed map row and ready requests from the input head.
    // Explicit occupancy reserves space for every entry before clearing the map.
    logic [_BITWIDTH_OUTPUT_FIFO_ADDR-1:0]          output_read_ptr, output_read_ptr_next;
    logic [_BITWIDTH_OUTPUT_FIFO_ADDR-1:0]          output_write_ptr, output_write_ptr_next;
    logic [_BITWIDTH_OUTPUT_FIFO_COUNT-1:0]         output_count, output_count_next;
    logic [(STRUCT_PRM_ENTRY_UPDATE*_BITWIDTH_OUTPUT_FIFO_ADDR)-1:0] output_read_addr;
    wire  [(STRUCT_PRM_ENTRY_UPDATE*_BITWIDTH_READY_PRM)-1:0] output_read_data;
    logic [(OUTPUT_PUSH_CHANNELS*_BITWIDTH_OUTPUT_FIFO_ADDR)-1:0] output_write_addr;
    logic [(OUTPUT_PUSH_CHANNELS*_BITWIDTH_READY_PRM)-1:0] output_write_data;
    logic [OUTPUT_PUSH_CHANNELS-1:0]                output_write_valid;
    logic [STRUCT_PRM_ENTRY_UPDATE-1:0]             output_valid;
    logic [_BITWIDTH_STRUCT_INST_STATE_ENTRIES-1:0] output_istentry       [0:STRUCT_PRM_ENTRY_UPDATE-1];
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0]            output_phyreg         [0:STRUCT_PRM_ENTRY_UPDATE-1];
    integer                                        output_pop_count, output_push_count;

    wire  [STRUCT_DECODE_NEW_INST-1:0]              allocate_valid;
    wire  [(STRUCT_DECODE_NEW_INST*_BITWIDTH_STRUCT_PHYREGS)-1:0] allocate_data;
    wire  [STRUCT_DECODE_NEW_INST-1:0]              allocate_fire;
    logic [STRUCT_UNALLOCATE_PHYREG-1:0]            unallocate_valid;
    wire  [STRUCT_UNALLOCATE_PHYREG-1:0]            unallocate_ready;
    logic [(STRUCT_UNALLOCATE_PHYREG*_BITWIDTH_STRUCT_PHYREGS)-1:0] unallocate_data;

    assign o_nel_phyreg_valid         = allocate_valid & {STRUCT_DECODE_NEW_INST{~input_stall}};
    assign o_nel_phyreg_data          = allocate_data;
    assign allocate_fire             = i_nel_phyreg_get & o_nel_phyreg_valid;
    assign o_ist_ready_phyreg_valid   = output_valid;
    assign input_buffer_write_data   = {i_ist_wait_phyreg_valid, i_ist_wait_phyreg_data};

    integer idx_input, idx_previous, idx_map0, idx_map1;
    integer idx_drain, drain_scan;
    integer idx_address, read_address;
    integer idx_output, idx_compare;
    integer idx_push, push_address;
    integer idx_state, idx_wait, idx_slot, idx_done, idx_allocate, idx_retire;
    integer counter_base, append_position, updated_count, retire_channel;
    integer drain_count, output_free_count;

    logic output_blocked;
    logic [_BITWIDTH_STRUCT_PHYREGS-1:0] target_phyreg;

    always_comb begin
        // Split Buffered Input Head and Gather Wait Requests
        wait_input_valid = input_buffer_read_data[(WAIT_INPUTS*_BITWIDTH_READY_PRM) +: WAIT_INPUTS]
                           & {WAIT_INPUTS{reset_n && (input_count != 0)}};
        wait_ready_valid = 0;
        wait_suffix_valid = 0;
        recv_input_valid = i_ist_wait_phyreg_valid;
        for (idx_input = 0; idx_input < WAIT_INPUTS; idx_input = idx_input+1) begin
            wait_input_list[idx_input] =
                input_buffer_read_data[(_BITWIDTH_READY_PRM*idx_input) +: _BITWIDTH_READY_PRM];
            wait_input_phyreg[idx_input] = wait_input_list[idx_input][0 +: _BITWIDTH_STRUCT_PHYREGS];
            wait_input_istentry[idx_input] =
                wait_input_list[idx_input][_BITWIDTH_STRUCT_PHYREGS +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES];

            // One notification updates every matching operand in the IST entry.
            for (idx_previous = 0; idx_previous < idx_input; idx_previous = idx_previous+1) begin
                if (wait_input_valid[idx_previous] && (wait_input_list[idx_input] == wait_input_list[idx_previous]))
                    wait_input_valid[idx_input] = 1'b0;
            end
            wait_map_list[idx_input] = 0;
            wait_ready_valid[idx_input] = wait_input_valid[idx_input] && phyreg_ready[wait_input_phyreg[idx_input]];
            if (wait_input_valid[idx_input] && !wait_ready_valid[idx_input])
                wait_map_list[idx_input][wait_input_phyreg[idx_input]] = 1'b1;

            recv_input_list[idx_input] = i_ist_wait_phyreg_data[(_BITWIDTH_READY_PRM*idx_input) +: _BITWIDTH_READY_PRM];
            recv_input_phyreg[idx_input] = recv_input_list[idx_input][0 +: _BITWIDTH_STRUCT_PHYREGS];
            for (idx_previous = 0; idx_previous < idx_input; idx_previous = idx_previous+1) begin
                if (recv_input_valid[idx_previous] && (recv_input_list[idx_input] == recv_input_list[idx_previous]))
                    recv_input_valid[idx_input] = 1'b0;
            end
        end

        // Transpose Input -> PHYREG into PHYREG -> Inputs.
        for (idx_map0 = 0; idx_map0 < STRUCT_PHYREGS; idx_map0 = idx_map0+1) begin
            for (idx_map1 = 0; idx_map1 < WAIT_INPUTS; idx_map1 = idx_map1+1)
                wait_map_phyreg[idx_map0][idx_map1] = wait_map_list[idx_map1][idx_map0];
        end

        // Prefix gives the append slot; only the last request writes the counter.
        for (idx_input = 0; idx_input < WAIT_INPUTS; idx_input = idx_input+1) begin
            wait_prefix_count[idx_input] = 0;
            for (idx_previous = 0; idx_previous < WAIT_INPUTS; idx_previous = idx_previous+1) begin
                if (wait_input_valid[idx_input] && wait_map_phyreg[wait_input_phyreg[idx_input]][idx_previous]) begin
                    if (idx_previous < idx_input)
                        wait_prefix_count[idx_input] = wait_prefix_count[idx_input]+1;
                    if (idx_previous > idx_input)
                        wait_suffix_valid[idx_input] = 1'b1;
                end
            end
        end

        // Select Completed Physical Register
        drain_valid = 1'b0;
        drain_phyreg = 0;
        drain_scan = 0;
        // One completed physical register per cycle, with round-robin arbitration.
        for (idx_drain = 0; idx_drain < STRUCT_PHYREGS; idx_drain = idx_drain+1) begin
            drain_scan = int'(drain_start)+idx_drain;
            if (drain_scan >= STRUCT_PHYREGS) drain_scan = drain_scan-STRUCT_PHYREGS;
            if (!drain_valid && phyreg_ready[drain_scan] && mapping_active[drain_scan]) begin
                drain_valid = reset_n;
                drain_phyreg = _BITWIDTH_STRUCT_PHYREGS'(drain_scan);
            end
        end

        // Mapping Counter / Map / Output FIFO Addresses
        counter_addr = 0;
        counter_addr[0 +: _BITWIDTH_STRUCT_PHYREGS] = drain_phyreg;
        mapping_write_addr = 0;
        mapping_write_data = 0;
        for (idx_address = 0; idx_address < WAIT_INPUTS; idx_address = idx_address+1) begin
            counter_addr[(_BITWIDTH_STRUCT_PHYREGS*(idx_address+1)) +: _BITWIDTH_STRUCT_PHYREGS] = wait_input_phyreg[idx_address];
            mapping_write_addr[(_BITWIDTH_STRUCT_PHYREGS*idx_address) +: _BITWIDTH_STRUCT_PHYREGS] = wait_input_phyreg[idx_address];
            mapping_write_data[(_BITWIDTH_STRUCT_INST_STATE_ENTRIES*idx_address) +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES] = wait_input_istentry[idx_address];
        end
        output_read_addr = 0;
        read_address = 0;
        for (idx_address = 0; idx_address < STRUCT_PRM_ENTRY_UPDATE; idx_address = idx_address+1) begin
            read_address = (int'(output_read_ptr)+idx_address)%OUTPUT_FIFO_ENTRIES;
            output_read_addr[(_BITWIDTH_OUTPUT_FIFO_ADDR*idx_address) +: _BITWIDTH_OUTPUT_FIFO_ADDR] = _BITWIDTH_OUTPUT_FIFO_ADDR'(read_address);
        end

        // Output FIFO -> IST
        output_valid = 0;
        output_pop_count = 0;
        output_blocked = 1'b0;
        o_ist_ready_phyreg_data = 0;
        for (idx_output = 0; idx_output < STRUCT_PRM_ENTRY_UPDATE; idx_output = idx_output+1) begin
            output_phyreg[idx_output] = output_read_data[(_BITWIDTH_READY_PRM*idx_output) +: _BITWIDTH_STRUCT_PHYREGS];
            output_istentry[idx_output] = output_read_data[(_BITWIDTH_READY_PRM*idx_output+_BITWIDTH_STRUCT_PHYREGS) +: _BITWIDTH_STRUCT_INST_STATE_ENTRIES];
            // Keep a contiguous FIFO prefix. Two updates to the same IST entry
            // are separated by a clock so its ready flags cannot overwrite each other.
            for (idx_compare = 0; idx_compare < idx_output; idx_compare = idx_compare+1) begin
                if (output_valid[idx_compare] && (output_istentry[idx_output] == output_istentry[idx_compare]))
                    output_blocked = 1'b1;
            end
            if (reset_n && (idx_output < output_count) && !output_blocked) begin
                output_valid[idx_output] = 1'b1;
                output_pop_count = output_pop_count+1;
                o_ist_ready_phyreg_data[(_BITWIDTH_READY_PRM*idx_output) +: _BITWIDTH_READY_PRM] =
                    output_read_data[(_BITWIDTH_READY_PRM*idx_output) +: _BITWIDTH_READY_PRM];
            end
        end

        // Check the Whole Input Bundle Before Updating Any Mapping
        input_map_fit = 1'b1;
        input_ready_count = 0;
        for (idx_input = 0; idx_input < WAIT_INPUTS; idx_input = idx_input+1) begin
            if (wait_ready_valid[idx_input]) input_ready_count = input_ready_count+1;
            if (wait_input_valid[idx_input] && !wait_ready_valid[idx_input]) begin
                if ((int'(counter_read_data[(_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER*(idx_input+1)) +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER])
                     +wait_prefix_count[idx_input]+1) > STRUCT_PRM_ENTRY_BUFFER)
                    input_map_fit = 1'b0;
            end
        end

        // Completed Map and Ready Input Requests -> Output FIFO
        // First reserve space for the old completed row. Buffered requests whose
        // PHYREG completed while waiting bypass the map; they must not wait for
        // another WBC pulse. The whole input head commits or remains unchanged.
        output_push_count = 0;
        output_write_addr = 0;
        output_write_data = 0;
        output_write_valid = 0;
        push_address = 0;
        drain_count = 0;
        output_free_count = OUTPUT_FIFO_ENTRIES-int'(output_count)+output_pop_count;
        if (drain_valid) drain_count = int'(counter_read_data[0 +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER]);
        drain_fire = drain_valid && (drain_count != 0) && (drain_count <= output_free_count);
        if (drain_fire) output_free_count = output_free_count-drain_count;
        input_fire = reset_n && (input_count != 0) && input_map_fit && (input_ready_count <= output_free_count);

        if (drain_fire) begin
            for (idx_push = 0; idx_push < STRUCT_PRM_ENTRY_BUFFER; idx_push = idx_push+1) begin
                if (idx_push < drain_count) begin
                    output_write_data[(_BITWIDTH_READY_PRM*output_push_count) +: _BITWIDTH_READY_PRM] =
                        {mapping_read_data[idx_push], drain_phyreg};
                    output_push_count = output_push_count+1;
                end
            end
        end
        if (input_fire) begin
            for (idx_push = 0; idx_push < WAIT_INPUTS; idx_push = idx_push+1) begin
                if (wait_ready_valid[idx_push]) begin
                    output_write_data[(_BITWIDTH_READY_PRM*output_push_count) +: _BITWIDTH_READY_PRM] =
                        wait_input_list[idx_push];
                    output_push_count = output_push_count+1;
                end
            end
        end
        for (idx_push = 0; idx_push < OUTPUT_PUSH_CHANNELS; idx_push = idx_push+1) begin
            push_address = (int'(output_write_ptr)+idx_push)%OUTPUT_FIFO_ENTRIES;
            output_write_addr[(_BITWIDTH_OUTPUT_FIFO_ADDR*idx_push) +: _BITWIDTH_OUTPUT_FIFO_ADDR] = _BITWIDTH_OUTPUT_FIFO_ADDR'(push_address);
            output_write_valid[idx_push] = (idx_push < output_push_count);
        end
        output_read_ptr_next = _BITWIDTH_OUTPUT_FIFO_ADDR'((int'(output_read_ptr)+output_pop_count)%OUTPUT_FIFO_ENTRIES);
        output_write_ptr_next = _BITWIDTH_OUTPUT_FIFO_ADDR'((int'(output_write_ptr)+output_push_count)%OUTPUT_FIFO_ENTRIES);
        output_count_next = _BITWIDTH_OUTPUT_FIFO_COUNT'(int'(output_count)-output_pop_count+output_push_count);

        // Input Buffer and PHYREG Allocation Backpressure
        // Do not mask IST input with input_stall: an already-renamed Stage 2
        // bundle may arrive once after new allocation stops. Reserve its slot.
        // NEL must stop EVERY Stage 1 -> Stage 2 transfer when offers are absent,
        // including instructions with no destination register, and deliver each
        // Stage 2 bundle to IST only once. No extra registered IST -> PRM stage.
        input_stall = !reset_n || ((input_count != 0) && !input_fire) ||
                      ((int'(input_count)-(input_fire? 1 : 0)) >= (INPUT_BUFFER_ENTRIES-1));
        input_push = reset_n && (|i_ist_wait_phyreg_valid) &&
                     ((input_count < INPUT_BUFFER_ENTRIES) || input_fire);
        input_read_ptr_next = input_read_ptr;
        input_write_ptr_next = input_write_ptr;
        input_count_next = _BITWIDTH_INPUT_BUFFER_COUNT'(int'(input_count)+(input_push? 1 : 0)-(input_fire? 1 : 0));
        if (input_fire) input_read_ptr_next = _BITWIDTH_INPUT_BUFFER_ADDR'((int'(input_read_ptr)+1)%INPUT_BUFFER_ENTRIES);
        if (input_push) input_write_ptr_next = _BITWIDTH_INPUT_BUFFER_ADDR'((int'(input_write_ptr)+1)%INPUT_BUFFER_ENTRIES);

        // Mapping Updates and Next State
        phyreg_ready_next = phyreg_ready;
        mapping_active_next = mapping_active;
        retired_pending_next = retired_pending;
        drain_start_next = drain_start;
        counter_write_valid = 0;
        counter_write_data = 0;
        unallocate_valid = 0;
        unallocate_data = 0;
        target_phyreg = 0;
        counter_base = 0;
        append_position = 0;
        updated_count = 0;
        retire_channel = 0;
        for (idx_state = 0; idx_state < STRUCT_PHYREGS; idx_state = idx_state+1)
            wait_count_next[idx_state] = wait_count[idx_state];
        for (idx_slot = 0; idx_slot < STRUCT_PRM_ENTRY_BUFFER; idx_slot = idx_slot+1)
            mapping_write_valid[idx_slot] = 0;

        // Release a map only after its entire batch has secured output FIFO space.
        if (drain_fire) begin
            counter_write_valid[0] = 1'b1;
            mapping_active_next[drain_phyreg] = 1'b0;
            if (drain_phyreg == STRUCT_PHYREGS-1) drain_start_next = 0;
            else drain_start_next = drain_phyreg+1'b1;
        end

        // Commit All Unfinished Requests in the Input Head Together
        // Ready requests go directly to the output FIFO above. On input overflow
        // no request in this bundle changes the map or counter; the head waits.
        for (idx_wait = 0; idx_wait < WAIT_INPUTS; idx_wait = idx_wait+1) begin
            if (input_fire && wait_input_valid[idx_wait] && !wait_ready_valid[idx_wait]) begin
                target_phyreg = wait_input_phyreg[idx_wait];
                counter_base = int'(counter_read_data[(_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER*(idx_wait+1)) +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER]);
                append_position = counter_base+wait_prefix_count[idx_wait];
                mapping_write_valid[append_position][idx_wait] = 1'b1;
                mapping_active_next[target_phyreg] = 1'b1;
                if (!wait_suffix_valid[idx_wait]) begin
                    updated_count = append_position+1;
                    counter_write_valid[idx_wait+1] = 1'b1;
                    counter_write_data[(_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER*(idx_wait+1)) +: _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER] =
                        _BITWIDTH_STRUCT_PRM_ENTRY_BUFFER'(updated_count);
                end
            end
        end

        // Count at input capture, not at map insertion, so buffered requests also
        // keep the old physical register lifetime alive. Replay never counts twice.
        for (idx_wait = 0; idx_wait < WAIT_INPUTS; idx_wait = idx_wait+1) begin
            if (input_push && recv_input_valid[idx_wait]) begin
                target_phyreg = recv_input_phyreg[idx_wait];
                wait_count_next[target_phyreg] = wait_count_next[target_phyreg]+1'b1;
            end
        end

        // Track notifications through the output FIFO as well as the input/map area.
        // Retiring a physical register must not recycle its number before delivery.
        for (idx_done = 0; idx_done < STRUCT_PRM_ENTRY_UPDATE; idx_done = idx_done+1) begin
            if (output_valid[idx_done])
                wait_count_next[output_phyreg[idx_done]] = wait_count_next[output_phyreg[idx_done]]-1'b1;
        end

        for (idx_allocate = 0; idx_allocate < STRUCT_DECODE_NEW_INST; idx_allocate = idx_allocate+1) begin
            if (allocate_fire[idx_allocate]) begin
                target_phyreg = allocate_data[(_BITWIDTH_STRUCT_PHYREGS*idx_allocate) +: _BITWIDTH_STRUCT_PHYREGS];
                phyreg_ready_next[target_phyreg] = 1'b0;
            end
        end
        for (idx_done = 0; idx_done < STRUCT_EX_OUT_RESULT_SUM; idx_done = idx_done+1) begin
            if (i_wbc_done_phyreg_valid[idx_done]) begin
                target_phyreg = i_wbc_done_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_done) +: _BITWIDTH_STRUCT_PHYREGS];
                phyreg_ready_next[target_phyreg] = 1'b1;
            end
        end
        phyreg_ready_next[0] = 1'b1;

        // FCL uses Valid-only delivery; retain returns until the allocator accepts.
        for (idx_retire = 0; idx_retire < STRUCT_UNALLOCATE_PHYREG; idx_retire = idx_retire+1) begin
            if (i_fcl_unallocate_phyreg_valid[idx_retire]) begin
                target_phyreg = i_fcl_unallocate_phyreg_data[(_BITWIDTH_STRUCT_PHYREGS*idx_retire) +: _BITWIDTH_STRUCT_PHYREGS];
                if (target_phyreg != 0) retired_pending_next[target_phyreg] = 1'b1;
            end
        end
        for (idx_state = 1; idx_state < STRUCT_PHYREGS; idx_state = idx_state+1) begin
            if (retired_pending[idx_state] && (wait_count_next[idx_state] == 0) &&
                (retire_channel < STRUCT_UNALLOCATE_PHYREG)) begin
                unallocate_valid[retire_channel] = reset_n;
                unallocate_data[(_BITWIDTH_STRUCT_PHYREGS*retire_channel) +: _BITWIDTH_STRUCT_PHYREGS] = _BITWIDTH_STRUCT_PHYREGS'(idx_state);
                if (reset_n && unallocate_ready[retire_channel]) retired_pending_next[idx_state] = 1'b0;
                retire_channel = retire_channel+1;
            end
        end
    end

    integer idx_reset;
    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            input_read_ptr <= 0;
            input_write_ptr <= 0;
            input_count <= 0;
            phyreg_ready <= {{(STRUCT_PHYREGS-1){1'b0}}, 1'b1};
            mapping_active <= 0;
            retired_pending <= 0;
            drain_start <= 0;
            output_read_ptr <= 0;
            output_write_ptr <= 0;
            output_count <= 0;
            for (idx_reset = 0; idx_reset < STRUCT_PHYREGS; idx_reset = idx_reset+1)
                wait_count[idx_reset] <= 0;
        end
        else begin
`ifndef SYNTHESIS
            // Valid-only input has no retry handshake. Reaching this condition
            // means the upstream stop / one-time admission contract was violated.
            if ((|i_ist_wait_phyreg_valid) && !input_push)
                $error("PRM input buffer overflow: NEL must stop on missing PHYREG offers and IST must send each admitted bundle once.");
`endif
            input_read_ptr <= input_read_ptr_next;
            input_write_ptr <= input_write_ptr_next;
            input_count <= input_count_next;
            phyreg_ready <= phyreg_ready_next;
            mapping_active <= mapping_active_next;
            retired_pending <= retired_pending_next;
            drain_start <= drain_start_next;
            output_read_ptr <= output_read_ptr_next;
            output_write_ptr <= output_write_ptr_next;
            output_count <= output_count_next;
            for (idx_reset = 0; idx_reset < STRUCT_PHYREGS; idx_reset = idx_reset+1)
                wait_count[idx_reset] <= wait_count_next[idx_reset];
        end
    end

    regfile #(
        .DATA_WIDTH    (_BITWIDTH_INPUT_BUNDLE),
        .ENTRIES       (INPUT_BUFFER_ENTRIES),
        .READ_CHANNEL  (1),
        .WRITE_CHANNEL (1),
        .INITIAL_VALUE (0)
    ) U_PRM_INPUT_BUFFER (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_read_addr   (input_read_ptr),
        .o_read_data   (input_buffer_read_data),
        .i_write_addr  (input_write_ptr),
        .i_write_en    (input_push),
        .i_write_data  (input_buffer_write_data)
    );

    allocator #(
        .ENTRIES            (STRUCT_PHYREGS-1),
        .START_VALUE        (1),
        .ALLOCATE_CHANNEL   (STRUCT_DECODE_NEW_INST),
        .UNALLOCATE_CHANNEL (STRUCT_UNALLOCATE_PHYREG),
        .USE_BRAM           (1'b1)
    ) U_PRM_PHYREG_ALLOCATOR (
        .clk                (clk),
        .reset_n            (reset_n),
        .i_flush            (1'b0),
        .i_unallocate       (unallocate_valid),
        .o_unallocate_ready (unallocate_ready),
        .i_unallocate_data  (unallocate_data),
        .i_allocate         (allocate_fire),
        .o_allocate_valid   (allocate_valid),
        .o_allocate_data    (allocate_data)
    );

    regfile #(
        .DATA_WIDTH    (_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER),
        .ENTRIES       (STRUCT_PHYREGS),
        .READ_CHANNEL  (COUNTER_CHANNELS),
        .WRITE_CHANNEL (COUNTER_CHANNELS),
        .INITIAL_VALUE (0)
    ) U_PRM_MAPPING_COUNTER (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_read_addr   (counter_addr),
        .o_read_data   (counter_read_data),
        .i_write_addr  (counter_addr),
        .i_write_en    (counter_write_valid),
        .i_write_data  (counter_write_data)
    );

    genvar mapping_idx;
    generate
        for (mapping_idx = 0; mapping_idx < STRUCT_PRM_ENTRY_BUFFER; mapping_idx = mapping_idx+1) begin : GEN_PRM_IST_MAP
            regfile #(
                .DATA_WIDTH    (_BITWIDTH_STRUCT_INST_STATE_ENTRIES),
                .ENTRIES       (STRUCT_PHYREGS),
                .READ_CHANNEL  (1),
                .WRITE_CHANNEL (WAIT_INPUTS),
                .INITIAL_VALUE (0)
            ) U_PRM_IST_MAP (
                .clk           (clk),
                .reset_n       (reset_n),
                .i_flush       (1'b0),
                .i_read_addr   (drain_phyreg),
                .o_read_data   (mapping_read_data[mapping_idx]),
                .i_write_addr  (mapping_write_addr),
                .i_write_en    (mapping_write_valid[mapping_idx]),
                .i_write_data  (mapping_write_data)
            );
        end

    endgenerate

    regfile #(
        .DATA_WIDTH    (_BITWIDTH_READY_PRM),
        .ENTRIES       (OUTPUT_FIFO_ENTRIES),
        .READ_CHANNEL  (STRUCT_PRM_ENTRY_UPDATE),
        .WRITE_CHANNEL (OUTPUT_PUSH_CHANNELS),
        .INITIAL_VALUE (0)
    ) U_PRM_OUTPUT_FIFO (
        .clk           (clk),
        .reset_n       (reset_n),
        .i_flush       (1'b0),
        .i_read_addr   (output_read_addr),
        .o_read_data   (output_read_data),
        .i_write_addr  (output_write_addr),
        .i_write_en    (output_write_valid),
        .i_write_data  (output_write_data)
    );
endmodule
