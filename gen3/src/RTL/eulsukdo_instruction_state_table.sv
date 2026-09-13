`timescale 1ns/1ps

module eulsukdo_instruction_state_table #(
    parameter int unsigned PC_WIDTH       = 32,
    parameter int unsigned OPERANDS       = 2,
    parameter int unsigned IMM_WIDTH      = 32,
    parameter int unsigned MICROOP_WIDTH  = 5,
    parameter int unsigned DECODE_WIDTH   = 2,
    parameter int unsigned IST_ENTRIES    = 128,
    parameter int unsigned PHY_REGS       = 64,
    parameter int unsigned EX_PATHS       = 3,
    parameter int unsigned FLOW_WINDOWS   = 8,
    parameter int unsigned WAKE_PORTS     = 5,
    parameter int unsigned DISPATCH_WIDTH = DECODE_WIDTH + WAKE_PORTS,
    parameter int unsigned IST_WIDTH      = (IST_ENTRIES <= 1) ? 1 : $clog2(IST_ENTRIES),
    parameter int unsigned PHY_REG_WIDTH  = (PHY_REGS <= 1) ? 1 : $clog2(PHY_REGS),
    parameter int unsigned EX_PATH_WIDTH  = (EX_PATHS <= 1) ? 1 : $clog2(EX_PATHS),
    parameter int unsigned FLOW_WIDTH     = (FLOW_WINDOWS <= 1) ? 1 : $clog2(FLOW_WINDOWS),
    parameter int unsigned INTERNAL_WIDTH = PC_WIDTH + FLOW_WIDTH + EX_PATH_WIDTH +
                                            MICROOP_WIDTH + IMM_WIDTH + PHY_REG_WIDTH +
                                            (OPERANDS * PHY_REG_WIDTH) + OPERANDS,
    parameter int unsigned ISSUE_WIDTH    = INTERNAL_WIDTH - OPERANDS,
    parameter int unsigned DEP_WIDTH      = PHY_REG_WIDTH + IST_WIDTH
) (
    input  logic                              clk,
    input  logic                              reset_n,

    input  logic [DECODE_WIDTH-1:0]           i_nel_valid,
    output logic [DECODE_WIDTH-1:0]           o_nel_get,
    input  logic [DECODE_WIDTH*INTERNAL_WIDTH-1:0] i_nel_data,

    output logic [DECODE_WIDTH*OPERANDS-1:0]  o_prm_dep_valid,
    output logic [DECODE_WIDTH*OPERANDS*DEP_WIDTH-1:0] o_prm_dep_data,
    output logic                              o_prm_dep_commit,
    input  logic                              i_prm_dep_ready,

    input  logic [WAKE_PORTS-1:0]             i_prm_wake_valid,
    output logic [WAKE_PORTS-1:0]             o_prm_wake_get,
    input  logic [WAKE_PORTS*DEP_WIDTH-1:0]   i_prm_wake_data,

    output logic [DISPATCH_WIDTH-1:0]         o_rs_valid,
    input  logic [DISPATCH_WIDTH-1:0]         i_rs_get,
    output logic [DISPATCH_WIDTH*ISSUE_WIDTH-1:0] o_rs_data
);
    localparam int unsigned P_RD    = PC_WIDTH + FLOW_WIDTH + EX_PATH_WIDTH + MICROOP_WIDTH + IMM_WIDTH;
    localparam int unsigned P_RS    = P_RD + PHY_REG_WIDTH;
    localparam int unsigned P_READY = P_RS + OPERANDS*PHY_REG_WIDTH;

    logic [IST_ENTRIES-1:0] occupied;
    logic [ISSUE_WIDTH-1:0] entry_data [0:IST_ENTRIES-1];
    logic [OPERANDS-1:0]    entry_ready [0:IST_ENTRIES-1];
    logic [PHY_REG_WIDTH-1:0] entry_source [0:IST_ENTRIES-1][0:OPERANDS-1];
    // The allocation index is independent of PRM ready. Verilator's process-level
    // dependency analysis sees the surrounding atomic-bundle handshake as a loop.
    /* verilator lint_off UNOPTFLAT */
    logic [IST_WIDTH-1:0] alloc_index [0:DECODE_WIDTH-1];
    /* verilator lint_on UNOPTFLAT */
    logic [IST_WIDTH-1:0] dispatch_index [0:DISPATCH_WIDTH-1];
    logic [IST_ENTRIES-1:0] alloc_used;
    logic [IST_ENTRIES-1:0] dispatch_used;
    logic enough_entries;
    logic bundle_accept;
    integer lane;
    integer operand;
    integer entry;
    integer wake;
    integer out_slot;
    integer needed;
    integer found;
    logic [PHY_REG_WIDTH-1:0] wake_phy;
    logic [IST_WIDTH-1:0] wake_ist;

    always_comb begin
        alloc_used = occupied;
        enough_entries = 1'b1;
        needed = 0;
        for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
            alloc_index[lane] = '0;
            if (i_nel_valid[lane]) begin
                needed = needed + 1;
                found = 0;
                for (entry = 0; entry < IST_ENTRIES; entry = entry + 1) begin
                    if (!alloc_used[entry] && (found == 0)) begin
                        alloc_index[lane] = IST_WIDTH'(entry);
                        alloc_used[entry] = 1'b1;
                        found = 1;
                    end
                end
                if (found == 0) enough_entries = 1'b0;
            end
        end

        o_nel_get = '0;
        if (enough_entries && i_prm_dep_ready) begin
            for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1)
                o_nel_get[lane] = i_nel_valid[lane];
        end
        bundle_accept = (needed != 0) && enough_entries && i_prm_dep_ready;

        o_prm_dep_commit = bundle_accept;

        o_rs_valid = '0;
        o_rs_data = '0;
        dispatch_used = '0;
        for (out_slot = 0; out_slot < DISPATCH_WIDTH; out_slot = out_slot + 1) begin
            dispatch_index[out_slot] = '0;
            found = 0;
            for (entry = 0; entry < IST_ENTRIES; entry = entry + 1) begin
                if (occupied[entry] && (&entry_ready[entry]) && !dispatch_used[entry] && (found == 0)) begin
                    dispatch_index[out_slot] = IST_WIDTH'(entry);
                    dispatch_used[entry] = 1'b1;
                    o_rs_valid[out_slot] = 1'b1;
                    o_rs_data[out_slot*ISSUE_WIDTH +: ISSUE_WIDTH] = entry_data[entry];
                    found = 1;
                end
            end
        end
    end

    always_comb begin
        o_prm_dep_valid = '0;
        o_prm_dep_data = '0;
        for (integer dep_lane = 0; dep_lane < DECODE_WIDTH; dep_lane = dep_lane + 1) begin
            for (integer dep_operand = 0; dep_operand < OPERANDS; dep_operand = dep_operand + 1) begin
                o_prm_dep_valid[dep_lane*OPERANDS+dep_operand] = i_nel_valid[dep_lane] &&
                    !i_nel_data[dep_lane*INTERNAL_WIDTH + P_READY + dep_operand];
                o_prm_dep_data[(dep_lane*OPERANDS+dep_operand)*DEP_WIDTH +: PHY_REG_WIDTH] =
                    i_nel_data[dep_lane*INTERNAL_WIDTH + P_RS + dep_operand*PHY_REG_WIDTH +: PHY_REG_WIDTH];
                o_prm_dep_data[(dep_lane*OPERANDS+dep_operand)*DEP_WIDTH + PHY_REG_WIDTH +: IST_WIDTH] =
                    alloc_index[dep_lane];
            end
        end
    end

    always_comb o_prm_wake_get = i_prm_wake_valid;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            occupied <= '0;
            for (entry = 0; entry < IST_ENTRIES; entry = entry + 1) begin
                entry_data[entry] <= '0;
                entry_ready[entry] <= '0;
                for (operand = 0; operand < OPERANDS; operand = operand + 1)
                    entry_source[entry][operand] <= '0;
            end
        end else begin
            for (wake = 0; wake < WAKE_PORTS; wake = wake + 1) begin
                if (i_prm_wake_valid[wake] && o_prm_wake_get[wake]) begin
                    wake_phy = i_prm_wake_data[wake*DEP_WIDTH +: PHY_REG_WIDTH];
                    wake_ist = i_prm_wake_data[wake*DEP_WIDTH + PHY_REG_WIDTH +: IST_WIDTH];
                    if (occupied[wake_ist]) begin
                        for (operand = 0; operand < OPERANDS; operand = operand + 1) begin
                            if (entry_source[wake_ist][operand] == wake_phy)
                                entry_ready[wake_ist][operand] <= 1'b1;
                        end
                    end
                end
            end

            for (out_slot = 0; out_slot < DISPATCH_WIDTH; out_slot = out_slot + 1) begin
                if (o_rs_valid[out_slot] && i_rs_get[out_slot]) begin
                    occupied[dispatch_index[out_slot]] <= 1'b0;
                    entry_ready[dispatch_index[out_slot]] <= '0;
                end
            end

            if (bundle_accept) begin
                for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
                    if (i_nel_valid[lane]) begin
                        occupied[alloc_index[lane]] <= 1'b1;
                        entry_data[alloc_index[lane]] <= i_nel_data[lane*INTERNAL_WIDTH +: ISSUE_WIDTH];
                        entry_ready[alloc_index[lane]] <=
                            i_nel_data[lane*INTERNAL_WIDTH + P_READY +: OPERANDS];
                        for (operand = 0; operand < OPERANDS; operand = operand + 1)
                            entry_source[alloc_index[lane]][operand] <=
                                i_nel_data[lane*INTERNAL_WIDTH + P_RS + operand*PHY_REG_WIDTH +: PHY_REG_WIDTH];
                    end
                end
            end
        end
    end

    initial begin
        if (IST_ENTRIES < DECODE_WIDTH || DISPATCH_WIDTH < 1)
            $error("Invalid EULSUKDO IST parameters");
    end
endmodule
