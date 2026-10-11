`timescale 1ns/1ps

// Pure-function equivalence: arbitrary occupancy and every rotation, compared
// with the original sequential allocator. Integration is tested separately.
module tb_ist_allocation #(
    parameter int ENTRIES = 128,
    parameter int DECODE = 2,
    parameter int BANKS = 8
);
    localparam int IDX_W = $clog2(ENTRIES);
    localparam int BANK_W = BANKS > 1 ? $clog2(BANKS) : 1;
    localparam int ROWS = (ENTRIES+BANKS-1)/BANKS;
    localparam int ALLOC_W = DECODE*(IDX_W+1);
    instruction_state_table #(
        .STRUCT_INST_STATE_ENTRIES(ENTRIES), .STRUCT_DECODE_NEW_INST(DECODE),
        .STRUCT_IST_BANKS(BANKS)
    ) dut (
        .clk(1'b0), .reset_n(1'b0),
        .i_nel_new_inst_valid('0), .o_nel_new_inst_get(), .i_nel_new_inst_data('0),
        .i_prm_ready_phyreg_valid('0), .i_prm_ready_phyreg_data('0),
        .i_rs_ready_inst_get('0), .o_rs_ready_inst_valid(), .o_rs_ready_inst_data(),
        .o_prm_wait_phyreg_valid(), .o_prm_wait_phyreg_data()
    );

    function automatic logic [ALLOC_W-1:0] reference_offers(
        input logic [ENTRIES-1:0] active, input int start_bank
    );
        int free_count[BANKS], free_row[BANKS];
        bit used[BANKS];
        int chosen, candidate;
        logic [ALLOC_W-1:0] result;
        result = 0;
        for (int b = 0; b < BANKS; b++) begin
            free_count[b] = 0; free_row[b] = 0; used[b] = 0;
            for (int r = ROWS-1; r >= 0; r--) begin
                if (r*BANKS+b < ENTRIES && !active[r*BANKS+b]) begin
                    free_count[b]++; free_row[b] = r;
                end
            end
        end
        for (int lane = 0; lane < DECODE; lane++) begin
            chosen = -1;
            for (int offset = 0; offset < BANKS; offset++) begin
                candidate = (start_bank+offset)%BANKS;
                if (!used[candidate] && free_count[candidate] != 0) begin
                    if (chosen < 0) chosen = candidate;
                    else if (free_count[candidate] > free_count[chosen]) chosen = candidate;
                end
            end
            if (chosen >= 0) begin
                used[chosen] = 1;
                result[DECODE*IDX_W+lane] = 1;
                result[lane*IDX_W +: IDX_W] = IDX_W'(free_row[chosen]*BANKS+chosen);
            end
        end
        return result;
    endfunction

    logic [ENTRIES-1:0] mask;
    logic [ALLOC_W-1:0] actual, expected;
    int checked = 0;
    int unsigned random_state = 32'habcd1234;
    function automatic int unsigned random_word();
        random_state ^= random_state << 13;
        random_state ^= random_state >> 17;
        random_state ^= random_state << 5;
        return random_state;
    endfunction
    task automatic check_all_rotations;
        for (int start_bank = 0; start_bank < BANKS; start_bank++) begin
            expected = reference_offers(mask, start_bank);
            actual = dut.allocation_offers(mask, BANK_W'(start_bank));
            if (actual !== expected)
                $fatal(1, "Allocation mismatch E=%0d D=%0d B=%0d start=%0d mask=%h expected=%h actual=%h",
                       ENTRIES, DECODE, BANKS, start_bank, mask, expected, actual);
            if (dut.allocation_capacity(mask) !== (&expected[DECODE*IDX_W +: DECODE]))
                $fatal(1, "Admission differs from full allocation E=%0d D=%0d B=%0d mask=%h",
                       ENTRIES, DECODE, BANKS, mask);
            checked++;
        end
    endtask
    initial begin
        #1;
        mask = '0; check_all_rotations();
        mask = '1; check_all_rotations();
        for (int p = 0; p < ENTRIES; p++) begin
            mask = '0; mask[p] = 1; check_all_rotations();
            mask = '1; mask[p] = 0; check_all_rotations();
        end
        for (int b = 0; b < BANKS; b++) begin
            mask = '1;
            for (int p = b; p < ENTRIES; p += BANKS) mask[p] = 0;
            check_all_rotations();
            mask = ~mask; check_all_rotations();
        end
        if (ENTRIES <= 8) begin
            for (int pattern = 0; pattern < (1 << ENTRIES); pattern++) begin
                mask = ENTRIES'(pattern); check_all_rotations();
            end
        end
        else begin
            for (int pattern = 0; pattern < 4096; pattern++) begin
                for (int p = 0; p < ENTRIES; p++) mask[p] = (random_word()%8) < (pattern%9);
                check_all_rotations();
            end
        end
        $display("PASS IST allocation E=%0d D=%0d B=%0d checked=%0d", ENTRIES, DECODE, BANKS, checked);
        $finish;
    end
endmodule
