`timescale 1ns/1ps

// Directed IST regression using the real allocator and regfiles.
// The scoreboard checks transfers and payloads independently of DUT state.
module tb_instruction_state_table #(
    parameter int DECODE = 2,
    parameter int OPERANDS = 2,
    parameter int UPDATES = 5,
    parameter int ENTRIES = 16
);
    localparam int PHY_W = 6;
    localparam int IDX_W = $clog2(ENTRIES);
    localparam int PAIR_W = IDX_W+PHY_W;
    localparam int RS_START = 32+3+2+5+32+PHY_W;
    localparam int EX_W = RS_START+OPERANDS*PHY_W;
    localparam int INST_W = EX_W+OPERANDS;
    localparam int OUTS = DECODE+UPDATES;

    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [DECODE-1:0] nel_valid, nel_get;
    logic [DECODE*INST_W-1:0] nel_data;
    logic [UPDATES-1:0] prm_valid;
    logic [UPDATES*PAIR_W-1:0] prm_data;
    logic [OUTS-1:0] rs_valid, rs_get;
    logic [OUTS*EX_W-1:0] rs_data;
    logic [DECODE*OPERANDS-1:0] wait_valid;
    logic [DECODE*OPERANDS*PAIR_W-1:0] wait_data;

    instruction_state_table #(
        .STRUCT_DECODE_NEW_INST (DECODE),
        .IS_INST_OPERANDS (OPERANDS),
        .STRUCT_PRM_ENTRY_UPDATE (UPDATES),
        .STRUCT_INST_STATE_ENTRIES (ENTRIES)
    ) dut (
        .clk (clk), .reset_n (reset_n),
        .i_nel_new_inst_valid (nel_valid), .o_nel_new_inst_get (nel_get), .i_nel_new_inst_data (nel_data),
        .i_prm_ready_phyreg_valid (prm_valid), .i_prm_ready_phyreg_data (prm_data),
        .i_rs_ready_inst_get (rs_get), .o_rs_ready_inst_valid (rs_valid), .o_rs_ready_inst_data (rs_data),
        .o_prm_wait_phyreg_valid (wait_valid), .o_prm_wait_phyreg_data (wait_data)
    );

    integer accepted [0:1023], seen [0:1023], slot_of [0:1023];
    integer slot_pc [0:ENTRIES-1];
    logic [EX_W-1:0] expected [0:1023];
    logic [OPERANDS-1:0] reference_ready [0:1023];
    integer request_count, accept_count, issue_count;
    integer pc, slot, preg, mapped_slot;
    logic [OUTS-1:0] stalled;
    logic [OUTS*EX_W-1:0] stalled_data;

    always @(posedge clk) begin
        if (!reset_n) begin
            request_count = 0; accept_count = 0; issue_count = 0;
            stalled = '0; stalled_data = '0;
            for (int p = 0; p < 1024; p++) begin
                accepted[p] = 0; seen[p] = 0; slot_of[p] = -1;
                expected[p] = '0; reference_ready[p] = '0;
            end
            for (int s = 0; s < ENTRIES; s++) slot_pc[s] = -1;
            if ((|nel_get) || (|wait_valid) || (|rs_valid)) $fatal(1, "Transfer during reset");
        end
        else begin
            // Notifications refer to entries allocated on earlier cycles.
            for (int u = 0; u < UPDATES; u++) begin
                if (prm_valid[u]) begin
                    slot = int'(prm_data[u*PAIR_W+PHY_W +: IDX_W]);
                    preg = int'(prm_data[u*PAIR_W +: PHY_W]);
                    if (slot < ENTRIES) begin
                        pc = slot_pc[slot];
                        if (pc >= 0) begin
                            for (int r = 0; r < OPERANDS; r++) begin
                                if (int'(expected[pc][RS_START+r*PHY_W +: PHY_W]) == preg)
                                    reference_ready[pc][r] = 1'b1;
                            end
                        end
                    end
                end
            end
            for (int d = 0; d < DECODE; d++) begin
                if (nel_valid[d] && (&nel_get)) begin
                    pc = int'(nel_data[d*INST_W +: 32]);
                    if (accepted[pc] != 0) $fatal(1, "Repeated NEL acceptance PC=%0d", pc);
                    accepted[pc]++; accept_count++;
                    expected[pc] = nel_data[d*INST_W +: EX_W];
                    reference_ready[pc] = nel_data[d*INST_W+EX_W +: OPERANDS];
                    mapped_slot = -1;
                    for (int r = 0; r < OPERANDS; r++) begin
                        if (wait_valid[d*OPERANDS+r] != !reference_ready[pc][r])
                            $fatal(1, "Wrong wait mask PC=%0d operand=%0d", pc, r);
                        if (wait_valid[d*OPERANDS+r]) begin
                            slot = int'(wait_data[(d*OPERANDS+r)*PAIR_W+PHY_W +: IDX_W]);
                            if (slot >= ENTRIES) $fatal(1, "Out-of-range allocation");
                            if ((mapped_slot >= 0) && (mapped_slot != slot)) $fatal(1, "Split allocation");
                            if ((slot_pc[slot] >= 0) && (slot_pc[slot] != pc)) $fatal(1, "Live entry overwritten");
                            if (wait_data[(d*OPERANDS+r)*PAIR_W +: PHY_W] != expected[pc][RS_START+r*PHY_W +: PHY_W])
                                $fatal(1, "Wrong physical register in wait request");
                            mapped_slot = slot; slot_pc[slot] = pc; slot_of[pc] = slot;
                            request_count++;
                        end
                    end
                end
                else if (|wait_valid[d*OPERANDS +: OPERANDS]) $fatal(1, "Wait request without acceptance");
            end
            for (int c = 0; c < OUTS; c++) begin
                if (stalled[c] && (!rs_valid[c] ||
                    (rs_data[c*EX_W +: EX_W] != stalled_data[c*EX_W +: EX_W])))
                    $fatal(1, "RS offer changed before handshake lane=%0d", c);
                if (rs_valid[c] && rs_get[c]) begin
                    pc = int'(rs_data[c*EX_W +: 32]);
                    if ((accepted[pc] != 1) || (seen[pc] != 0)) $fatal(1, "Unexpected/duplicate issue PC=%0d", pc);
                    if (!(&reference_ready[pc])) $fatal(1, "Early issue PC=%0d", pc);
                    if (rs_data[c*EX_W +: EX_W] != expected[pc]) $fatal(1, "Corrupted payload PC=%0d", pc);
                    seen[pc]++; issue_count++;
                    if (slot_of[pc] >= 0) slot_pc[slot_of[pc]] = -1;
                end
            end
            stalled = rs_valid & ~rs_get;
            stalled_data = rs_data;
        end
    end

    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask

    function automatic logic [INST_W-1:0] instruction(input int id, input logic [OPERANDS-1:0] ready_bits, input bit same_source);
        logic [INST_W-1:0] data;
        data = '0;
        data[0 +: 32] = 32'(id);
        data[32 +: 3] = 3'(id);
        data[37 +: 5] = 5'(id);
        data[42 +: 32] = 32'(id*17);
        data[RS_START-PHY_W +: PHY_W] = PHY_W'(id);
        for (int r = 0; r < OPERANDS; r++) data[RS_START+r*PHY_W +: PHY_W] = PHY_W'(same_source ? 9 : r+1);
        data[EX_W +: OPERANDS] = ready_bits;
        return data;
    endfunction

    task automatic await_get;
        for (int t = 0; t < 200; t++) begin
            #1;
            if (&nel_get) return;
            step();
        end
        $fatal(1, "NEL Get did not recover: accepted=%0d issued=%0d fill=%0d offers=%b active=%h pending=%h", accept_count, issue_count, fill_count, dut.allocate_valid, dut.active_entries, dut.pending_entries);
    endtask

    task automatic send_one(input int id, input logic [OPERANDS-1:0] ready_bits, input bit same_source = 0);
        await_get();
        nel_valid = '0; nel_valid[0] = 1;
        nel_data = '0; nel_data[0 +: INST_W] = instruction(id, ready_bits, same_source);
        step(); nel_valid = '0;
    endtask

    task automatic notify_slot(input int lane, input int target_slot, input int phy);
        prm_valid[lane] = 1'b1;
        prm_data[lane*PAIR_W +: PAIR_W] = {IDX_W'(target_slot), PHY_W'(phy)};
    endtask

    task automatic await_issue(input int id);
        for (int t = 0; t < 200; t++) begin
            if (seen[id] == 1) return;
            step();
        end
        $fatal(1, "Instruction did not issue PC=%0d", id);
    endtask

    logic [OPERANDS-1:0] mask;
    integer saved_requests, saved_slot, fill_count;
    initial begin
        nel_valid = '0; nel_data = '0; prm_valid = '0; prm_data = '0; rs_get = '1;
        repeat (3) step(); reset_n = 1;
        await_get();

        // Already-ready instructions bypass; sparse allocation within a bundle.
        send_one(1, '1); await_issue(1);
        if (DECODE > 1) begin
            await_get(); nel_valid = '0; nel_data = '0;
            nel_valid[0] = 1; nel_valid[DECODE-1] = 1;
            nel_data[0 +: INST_W] = instruction(2, '1, 0);
            mask = '1; mask[0] = 0;
            nel_data[(DECODE-1)*INST_W +: INST_W] = instruction(3, mask, 0);
            step(); nel_valid = '0;
            notify_slot(0, slot_of[3], 1); step(); prm_valid = '0;
            await_issue(2); await_issue(3);
        end

        // Ready flags must accumulate across cycles, including a high PRM lane.
        mask = '1; mask[0] = 0; mask[OPERANDS-1] = 0;
        send_one(4, mask);
        notify_slot(UPDATES-1, slot_of[4], 1); step(); prm_valid = '0;
        repeat (3) step();
        if (seen[4] != 0) $fatal(1, "Lost a dependency");
        notify_slot(0, slot_of[4], 63); step(); prm_valid = '0;
        notify_slot(0, slot_of[4], OPERANDS); step(); prm_valid = '0;
        await_issue(4);

        // Two different operands in one cycle must merge into one table write.
        send_one(5, mask);
        notify_slot(0, slot_of[5], 1); notify_slot(UPDATES-1, slot_of[5], OPERANDS);
        step(); prm_valid = '0; await_issue(5);

        // Repeated source operands and duplicate notifications issue only once.
        send_one(6, '0, 1); saved_slot = slot_of[6];
        notify_slot(0, saved_slot, 9); notify_slot(UPDATES-1, saved_slot, 9);
        step(); prm_valid = '0; await_issue(6);
        notify_slot(0, saved_slot, 9); step(); prm_valid = '0;
        repeat (4) step();

        // PRM pulses continue during backpressure. One already-ready NEL bundle
        // is buffered, then further NEL admission stops until that bundle drains.
        send_one(7, '0, 1); saved_requests = request_count;
        rs_get = '0;
        nel_valid = '1;
        for (int d = 0; d < DECODE; d++) nel_data[d*INST_W +: INST_W] = instruction(20+d, '1, 0);
        notify_slot(0, slot_of[7], 9); step(); prm_valid = '0; nel_valid = '0;
        repeat (8) step();
        if ((seen[7] != 0) || (request_count != saved_requests) || (|nel_get)) $fatal(1, "Stall was not retained");
        if (!rs_valid[0] || !(&rs_valid[UPDATES +: DECODE])) $fatal(1, "Valid depends on Get");
        // Partial Get permits only the corresponding pending output channel.
        rs_get[0] = 1; await_issue(7);
        if (accepted[20] != 1 || seen[20] != 0) $fatal(1, "Ready bypass was not buffered");
        // Drain ready bypass lanes separately, including the highest lane first.
        rs_get = '0;
        for (int d = DECODE-1; d >= 0; d--) begin
            rs_get[UPDATES+d] = 1'b1;
            step();
            rs_get[UPDATES+d] = 1'b0;
        end
        rs_get = '1;
        for (int d = 0; d < DECODE; d++) await_issue(20+d);

        // Fill until fewer than DECODE offers remain. No ready notifications
        // are sent, so no entry can legitimately be reused during this phase.
        fill_count = 0;
        for (int b = 0; b < ENTRIES/DECODE; b++) begin
            await_get(); nel_valid = '1;
            for (int d = 0; d < DECODE; d++) nel_data[d*INST_W +: INST_W] = instruction(100+b*DECODE+d, '0, 1);
            step(); nel_valid = '0; fill_count += DECODE;
        end
        saved_requests = request_count;
        nel_valid = '1;
        for (int d = 0; d < DECODE; d++) nel_data[d*INST_W +: INST_W] = instruction(300+d, '0, 1);
        repeat (8) step();
        if ((|nel_get) || (request_count != saved_requests)) $fatal(1, "Full table accepted input");
        nel_valid = '0; rs_get = '0;
        for (int n = 0; n < fill_count; n += UPDATES) begin
            for (int u = 0; u < UPDATES; u++) begin
                if (n+u < fill_count) notify_slot(u, slot_of[100+n+u], 9);
            end
            step(); prm_valid = '0;
        end
        // A receiver may wait for Valid before asserting Get. Accept sparse,
        // changing lanes and verify other lanes retain their exact payloads.
        repeat (3) step();
        for (int t = 0; t < fill_count*4; t++) begin
            #1;
            for (int c = 0; c < OUTS; c++) rs_get[c] = rs_valid[c] && ((t+c)%3 != 0);
            step();
        end
        rs_get = '1;
        for (int n = 0; n < fill_count; n++) await_issue(100+n);
        await_get();

        // Repeated full-table lifetimes exercise returned entry numbers.
        for (int round_idx = 0; round_idx < 3; round_idx++) begin
            for (int b = 0; b < ENTRIES/DECODE; b++) begin
                await_get(); nel_valid = '1;
                for (int d = 0; d < DECODE; d++) nel_data[d*INST_W +: INST_W] = instruction(400+round_idx*ENTRIES+b*DECODE+d, '0, 1);
                step(); nel_valid = '0;
            end
            for (int n = 0; n < fill_count; n += UPDATES) begin
                for (int u = 0; u < UPDATES; u++) begin
                    if (n+u < fill_count) notify_slot(u, slot_of[400+round_idx*ENTRIES+n+u], 9);
                end
                step(); prm_valid = '0;
            end
            for (int n = 0; n < fill_count; n++) await_issue(400+round_idx*ENTRIES+n);
        end

        repeat (10) step();
        if (accept_count != issue_count) $fatal(1, "Lost instructions accepted=%0d issued=%0d", accept_count, issue_count);
        // Reset discards an occupied entry and suppresses all transfer pulses.
        send_one(900, '0, 1); rs_get = '0;
        notify_slot(0, slot_of[900], 9); step(); prm_valid = '0;
        reset_n = 0; repeat (2) step();
        reset_n = 1; rs_get = '1;
        send_one(901, '1); await_issue(901);
        repeat (5) step();
        $display("PASS IST DECODE=%0d OPERANDS=%0d UPDATES=%0d ENTRIES=%0d", DECODE, OPERANDS, UPDATES, ENTRIES);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "Watchdog timeout");
    end
endmodule
