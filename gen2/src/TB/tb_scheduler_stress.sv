`timescale 1ns/1ps

// Independent program-order dependency scoreboard; EX may issue and complete
// out of order across all three paths. No DUT internals are used for correctness.
module tb_scheduler_stress #(
    parameter int DECODE = 2,
    parameter int WINDOWS = 8,
    parameter int RANGE = 16,
    parameter int IST_ENTRIES = 128,
    parameter int UPDATES = 5,
    parameter int SEED = 1,
    parameter int COUNT = 384
);
    localparam int FLOW_W = WINDOWS > 1 ? $clog2(WINDOWS) : 1;
    localparam int TAG_W = FLOW_W+32;
    localparam int RD_OFFSET = TAG_W+2+5+32;
    localparam int INST_W = RD_OFFSET+18;
    localparam int RESULT_W = TAG_W+6;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [DECODE-1:0] req_valid, req_get, im_valid, im_get, newreg;
    logic [DECODE*TAG_W-1:0] req_pc, im_pc;
    logic [DECODE*2-1:0] path;
    logic [DECODE*5-1:0] microop, rd;
    logic [DECODE*10-1:0] rs;
    logic [DECODE*32-1:0] imm;
    logic [4:0] ex_valid, ex_get, wb_valid;
    logic [5*INST_W-1:0] ex_data;
    logic [5*RESULT_W-1:0] wb_data;
    logic [TAG_W-1:0] requests[$], tags[COUNT];
    int latest[32], source[COUNT][2], physical[COUNT], due[COUNT], value_version[64];
    bit accepted[COUNT], issued[COUNT], done[COUNT], scheduled[COUNT];
    bit used_physical[64];
    int cycle, fetched, received, issue_count, done_count, out_of_order;
    int path_count[3], backpressure, epoch, overflow_stall, recycled, completion_ooo;
    logic [31:0] rng;

    function automatic int dst(input int id);
        if (id == 0) return 1;
        if (id < 13) return id+1;
        if ((id % 11) == 0) return 0;
        // Adjacent writers deliberately exercise same-bundle WAW.
        return 1+((id/3) % 15);
    endfunction
    function automatic bit writes(input int id);
        return (id < 13) || ((id % 5) != 0);
    endfunction
    function automatic int src(input int id, input int operand);
        if (id == 0) return 0;
        if (id < 13) return 1; // Duplicate operands and PRM row overflow.
        if (operand == 0) return (id % 4 == 0) ? 0 : dst(id);
        return 1+((id*7) % 15);
    endfunction
    function automatic logic [31:0] immediate(input int id);
        return 32'(id) ^ 32'h13579bdf;
    endfunction
    function automatic int random_word();
        rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
        return int'(rng & 32'h7fffffff);
    endfunction

    eulsukdo_scheduler #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_FLOW_WINDOWS(WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(RANGE), .STRUCT_INST_STATE_ENTRIES(IST_ENTRIES),
        .STRUCT_PRM_ENTRY_UPDATE(UPDATES)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .o_im_req_pc_valid(req_valid), .i_im_req_pc_get(req_get), .o_im_req_pc(req_pc),
        .i_im_recv_inst_valid(im_valid), .o_im_recv_inst_get(im_get), .i_im_recv_pc(im_pc), .i_im_recv_inst('0),
        .i_nel_decode_exception('0), .i_nel_decode_expath(path), .i_nel_decode_microop(microop),
        .i_nel_decode_rd(rd), .i_nel_decode_newreg(newreg), .i_nel_decode_rs(rs), .i_nel_decode_imm(imm),
        .i_nel_decode_jump('0), .i_nel_decode_jump_reg('0), .i_nel_decode_branch('0),
        .o_rs_entry_valid(ex_valid), .i_rs_entry_get(ex_get), .o_rs_entry_data(ex_data),
        .i_wbc_result_valid(wb_valid), .i_wbc_result_data(wb_data),
        .i_wbc_result_branch_valid('0), .i_wbc_result_branch_data('0)
    );

    always_comb begin
        path = '0; microop = '0; rd = '0; rs = '0; imm = '0; newreg = '0;
        for (int d = 0; d < DECODE; d++) begin
            path[d*2 +: 2] = 2'((im_pc[d*TAG_W +: 32]/4) % 3);
            microop[d*5 +: 5] = 5'(im_pc[d*TAG_W +: 32]/4);
            rd[d*5 +: 5] = 5'(dst(int'(im_pc[d*TAG_W +: 32]/4)));
            newreg[d] = writes(int'(im_pc[d*TAG_W +: 32]/4));
            imm[d*32 +: 32] = immediate(int'(im_pc[d*TAG_W +: 32]/4));
            for (int s = 0; s < 2; s++)
                rs[d*10+s*5 +: 5] = 5'(src(int'(im_pc[d*TAG_W +: 32]/4), s));
        end
    end

    always @(posedge clk) begin : model
        int id, producer, preg, lane, expected_path;
        if (!reset_n) begin
            cycle = 0; fetched = 0; received = 0; issue_count = 0; done_count = 0;
            out_of_order = 0; backpressure = 0; overflow_stall = 0; recycled = 0; completion_ooo = 0; rng = 32'(SEED+epoch);
            requests.delete(); im_valid <= '0; im_pc <= '0;
            req_get <= '0; ex_get <= '0; wb_valid <= '0; wb_data <= '0;
            for (int r = 0; r < 32; r++) latest[r] = -1;
            for (int r = 0; r < 64; r++) begin used_physical[r] = 0; value_version[r] = -1; end
            for (int p = 0; p < 3; p++) path_count[p] = 0;
            for (int i = 0; i < COUNT; i++) begin
                accepted[i] = 0; issued[i] = 0; done[i] = 0; scheduled[i] = 0;
                physical[i] = 0; due[i] = 0; tags[i] = '0;
                for (int s = 0; s < 2; s++) source[i][s] = -1;
            end
        end else begin
            cycle++;
            // Internal signals are used only to establish overflow coverage.
            if (dut.U_PHYSICAL_REGISTER_MAPPER.input_count != 0 &&
                !dut.U_PHYSICAL_REGISTER_MAPPER.input_map_fit) overflow_stall++;
            req_get <= {DECODE{(fetched < COUNT) && (cycle % 7 != 0)}};
            // Completions become visible to the DUT on this edge.
            for (int e = 0; e < 5; e++) if (wb_valid[e]) begin
                id = int'(wb_data[e*RESULT_W +: 32]/4);
                if (!issued[id] || done[id]) $fatal(1, "Invalid completion id=%0d", id);
                for (int older = 0; older < id; older++)
                    if (!done[older]) begin completion_ooo++; break; end
                if (physical[id] != 0) value_version[physical[id]] = id;
                done[id] = 1; done_count++;
            end
            for (int d = 0; d < DECODE; d++) begin
                if (req_valid[d] && req_get[d]) begin
                    if (req_pc[d*TAG_W +: 32] != 32'(fetched*4)) $fatal(1, "Fetch sequence lost");
                    requests.push_back(req_pc[d*TAG_W +: TAG_W]); fetched++;
                end
                if (im_valid[d] && im_get[d]) begin
                    id = int'(im_pc[d*TAG_W +: 32]/4);
                    if (id != received || accepted[id]) $fatal(1, "IM sequence lost");
                    accepted[id] = 1; received++; tags[id] = im_pc[d*TAG_W +: TAG_W];
                    for (int s = 0; s < 2; s++) source[id][s] = latest[src(id, s)];
                    if (writes(id) && dst(id) != 0) latest[dst(id)] = id;
                end
            end
            if (|(im_valid & ~im_get)) backpressure++;
            im_valid <= im_valid & ~im_get;
            if (!(|im_valid) && cycle % 4 != 0) begin
                for (int d = 0; d < DECODE; d++) begin
                    if (requests.size() != 0) begin
                        im_valid[d] <= 1;
                        im_pc[d*TAG_W +: TAG_W] <= requests.pop_front();
                    end
                end
            end
            for (int e = 0; e < 5; e++) begin
                if (ex_valid[e] && ex_get[e]) begin
                    id = int'(ex_data[e*INST_W +: 32]/4);
                    if (id >= COUNT || !accepted[id] || issued[id]) $fatal(1, "Lost/duplicate issue id=%0d", id);
                    expected_path = e == 0 ? 0 : (e == 4 ? 2 : 1);
                    if (id % 3 != expected_path || ex_data[e*INST_W+TAG_W +: 2] != 2'(expected_path))
                        $fatal(1, "Wrong EX path id=%0d lane=%0d", id, e);
                    if (ex_data[e*INST_W +: TAG_W] != tags[id] ||
                        ex_data[e*INST_W+TAG_W+2 +: 5] != 5'(id) ||
                        ex_data[e*INST_W+TAG_W+7 +: 32] != immediate(id)) $fatal(1, "Corrupted payload id=%0d", id);
                    for (int s = 0; s < 2; s++) begin
                        producer = source[id][s]; preg = 0;
                        if (producer >= 0) begin
                            if (!done[producer]) $fatal(1, "Early RAW issue id=%0d producer=%0d", id, producer);
                            preg = physical[producer];
                        end
                        if (value_version[preg] != producer)
                            $fatal(1, "Source value overwritten before reader issued id=%0d producer=%0d", id, producer);
                        if (ex_data[e*INST_W+RD_OFFSET+6+s*6 +: 6] != 6'(preg))
                            $fatal(1, "Wrong source rename id=%0d operand=%0d", id, s);
                    end
                    physical[id] = int'(ex_data[e*INST_W+RD_OFFSET +: 6]);
                    if ((physical[id] != 0) != (writes(id) && dst(id) != 0)) $fatal(1, "x0/no-RD allocation error");
                    if (physical[id] != 0) begin
                        if (used_physical[physical[id]]) recycled++;
                        used_physical[physical[id]] = 1;
                        for (int older = 0; older < COUNT; older++)
                            if (issued[older] && !done[older] && physical[older] == physical[id])
                                $fatal(1, "Physical number reused while writer in flight");
                    end
                    for (int older = 0; older < id; older++)
                        if (!done[older]) begin out_of_order++; break; end
                    issued[id] = 1; issue_count++; path_count[expected_path]++;
                    due[id] = cycle + ((id == 0) ? 100 : (2+random_word()%25));
                end
                // Sparse EX acceptance, with long stalls on individual paths.
                ex_get[e] <= ((cycle % 101) > (e*4+5)) && ((random_word()%4) != 0);
            end
            wb_valid <= '0; wb_data <= '0; lane = 0;
            // Reverse scan deliberately reorders ready completions.
            for (int i = COUNT-1; i >= 0; i--) begin
                if (issued[i] && !scheduled[i] && due[i] <= cycle && lane < 5) begin
                    wb_valid[lane] <= 1;
                    wb_data[lane*RESULT_W +: RESULT_W] <= {6'(physical[i]), tags[i]};
                    scheduled[i] = 1; lane++;
                end
            end
        end
    end

    initial begin
        if (COUNT % RANGE != 0) $fatal(1, "COUNT must end on a complete flow window");
        for (epoch = 0; epoch < 2; epoch++) begin
            reset_n = 0; repeat (3) @(negedge clk); reset_n = 1;
            for (int t = 0; t < 30000 && done_count < COUNT; t++) @(negedge clk);
            if (done_count != COUNT || issue_count != COUNT || received != COUNT)
                $fatal(1, "Stress stalled fetched=%0d received=%0d issued=%0d completed=%0d req=%b im=%b queue=%0d FCL pending=%b received=%0d kept=%0d renamed=%0d",
                    fetched, received, issue_count, done_count, req_valid, im_valid, requests.size(),
                    dut.U_FLOW_CONTROL_LOGIC.request_pending, dut.U_FLOW_CONTROL_LOGIC.received,
                    dut.U_FLOW_CONTROL_LOGIC.kept, dut.U_FLOW_CONTROL_LOGIC.renamed);
            repeat (100) @(negedge clk);
            if (issue_count != COUNT || done_count != COUNT) $fatal(1, "Extra issue after drain");
            for (int p = 0; p < 3; p++) if (path_count[p] == 0) $fatal(1, "Missing EX path coverage");
            if (out_of_order == 0 || completion_ooo == 0) $fatal(1, "Missing out-of-order coverage");
            if (overflow_stall == 0 || recycled == 0) $fatal(1, "Missing PRM overflow/recycling coverage");
            $display("epoch=%0d count=%0d cycles=%0d overlapping_issue=%0d OOO_completion=%0d IM_stall=%0d PRM_overflow=%0d recycled=%0d paths=%0d,%0d,%0d",
                epoch, done_count, cycle, out_of_order, completion_ooo, backpressure, overflow_stall, recycled,
                path_count[0], path_count[1], path_count[2]);
        end
        $display("PASS scheduler stress D=%0d WINDOWS=%0d RANGE=%0d IST=%0d U=%0d SEED=%0d", DECODE, WINDOWS, RANGE, IST_ENTRIES, UPDATES, SEED);
        $finish;
    end
    initial begin #1000000; $fatal(1, "Stress watchdog"); end
endmodule
