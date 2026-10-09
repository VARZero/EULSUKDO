`timescale 1ns/1ps

// Full gen2 scheduler smoke test with an in-order IM responder and a delayed
// EX model. WRITES=0 covers no-RD/x0 control flow; WRITES=1 repeatedly reads and
// overwrites logical r1, exercising RAW wakeups and physical-register recycling.
module tb_scheduler_flow #(
    parameter int DECODE = 3,
    parameter int WINDOWS = 3,
    parameter int RANGE = 5,
    parameter int UPDATES = 3,
    parameter int WRITES = 0
);
    localparam int FLOW_W = (WINDOWS > 1)? $clog2(WINDOWS) : 1;
    localparam int TAG_W = 32+FLOW_W;
    localparam int INST_W = TAG_W+2+5+32+6+12;
    localparam int RESULT_W = TAG_W+6;
    localparam int BR_W = TAG_W+32;
    localparam int TARGET = WRITES ? 160 : 40;
    logic clk = 0, reset_n = 0;
    always #5 clk = ~clk;
    logic [DECODE-1:0] req_valid, req_get, im_valid, im_get;
    logic [DECODE*TAG_W-1:0] req_pc, im_pc;
    logic [DECODE-1:0] jump, jreg, branch;
    logic [DECODE*32-1:0] imm;
    logic [DECODE-1:0] newreg;
    logic [DECODE*5-1:0] rd;
    logic [DECODE*10-1:0] rs;
    logic [5-1:0] ex_valid, ex_get, wb_valid;
    logic [5*INST_W-1:0] ex_data;
    logic [5*RESULT_W-1:0] wb_data;
    logic branch_result_valid;
    logic [BR_W-1:0] branch_result_data;
    logic [RESULT_W-1:0] results[$];
    int result_times[$];
    logic [TAG_W-1:0] result_tag;
    logic [RESULT_W-1:0] result_entry;
    int ignored_time, cycle, issued, completed, expected_pc, pc, out_lane;
    logic [DECODE-1:0] receive_mask;
    logic [DECODE*TAG_W-1:0] response_pc;

    eulsukdo_scheduler #(
        .STRUCT_DECODE_NEW_INST(DECODE), .STRUCT_FLOW_WINDOWS(WINDOWS),
        .STRUCT_FLOW_PC_MAX_RANGE(RANGE), .STRUCT_INST_STATE_ENTRIES(16),
        .STRUCT_PRM_ENTRY_UPDATE(UPDATES)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .o_im_req_pc_valid(req_valid), .i_im_req_pc_get(req_get), .o_im_req_pc(req_pc),
        .i_im_recv_inst_valid(im_valid), .o_im_recv_inst_get(im_get), .i_im_recv_pc(im_pc), .i_im_recv_inst('0),
        .i_nel_decode_exception('0), .i_nel_decode_expath('0), .i_nel_decode_microop('0),
        .i_nel_decode_rd(rd), .i_nel_decode_newreg(newreg), .i_nel_decode_rs(rs),
        .i_nel_decode_imm(imm), .i_nel_decode_jump(jump), .i_nel_decode_jump_reg(jreg), .i_nel_decode_branch(branch),
        .o_rs_entry_valid(ex_valid), .i_rs_entry_get(ex_get), .o_rs_entry_data(ex_data),
        .i_wbc_result_valid(wb_valid), .i_wbc_result_data(wb_data),
        .i_wbc_result_branch_valid(branch_result_valid), .i_wbc_result_branch_data(branch_result_data)
    );

    assign req_get = {DECODE{reset_n && !(|im_valid) && !(|receive_mask) && (issued < TARGET)}};
    assign ex_get = {5{reset_n && ((cycle % 7) >= 3)}};
    always_comb begin
        jump = '0; jreg = '0; branch = '0; imm = '0;
        rd = '0; rs = '0; newreg = '0;
        for (int d = 0; d < DECODE; d++) begin
            case (im_pc[d*TAG_W +: 32])
                4: begin jump[d] = 1; imm[d*32 +: 32] = 12; end
                16: begin branch[d] = 1; imm[d*32 +: 32] = 16; end
                32: begin branch[d] = 1; imm[d*32 +: 32] = 64; end
                36: jreg[d] = 1;
                default: begin
                    if (WRITES != 0) begin
                        rd[d*5 +: 5] = 5'd1; rs[d*10 +: 5] = 5'd1; newreg[d] = 1;
                    end
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (!reset_n) begin
            im_valid <= '0; im_pc <= '0; receive_mask = '0; response_pc = '0;
            wb_valid <= '0; wb_data <= '0; branch_result_valid <= 0; branch_result_data <= '0;
            results.delete(); result_times.delete(); cycle = 0; issued = 0; completed = 0; expected_pc = 0;
        end
        else begin
            cycle++;
            im_valid <= im_valid & ~im_get;
            // Collect a requested bundle, then send one response at a time in
            // program order. This exercises branch tails arriving on later cycles.
            for (int d = 0; d < DECODE; d++) begin
                if (req_valid[d] && req_get[d]) begin
                    receive_mask[d] = 1;
                    response_pc[d*TAG_W +: TAG_W] = req_pc[d*TAG_W +: TAG_W];
                end
            end
            if (!(|im_valid)) begin
                for (int d = 0; d < DECODE; d++) begin
                    if (receive_mask[d]) begin
                        im_valid <= DECODE'(1); im_pc <= '0;
                        im_pc[0 +: TAG_W] <= response_pc[d*TAG_W +: TAG_W];
                        receive_mask[d] = 0; break;
                    end
                end
            end

            for (int e = 0; e < 5; e++) begin
                if (ex_valid[e] && ex_get[e]) begin
                    pc = int'(ex_data[e*INST_W +: 32]);
                    if (pc != expected_pc) $fatal(1, "Wrong-path, lost, or repeated instruction: wanted=%0d got=%0d", expected_pc, pc);
                    issued++;
                    case (pc)
                        4: expected_pc = 16;
                        16: expected_pc = 32;
                        32: expected_pc = 36;
                        36: expected_pc = 48;
                        default: expected_pc = pc+4;
                    endcase
                    results.push_back({ex_data[e*INST_W+TAG_W+2+5+32 +: 6], ex_data[e*INST_W +: TAG_W]});
                    result_times.push_back(cycle+3);
                end
            end
            wb_valid <= '0; wb_data <= '0; branch_result_valid <= 0;
            out_lane = 0;
            while ((results.size() != 0) && (out_lane < 5)) begin
                if (result_times[0] > cycle) break;
                result_entry = results.pop_front(); result_tag = result_entry[0 +: TAG_W];
                ignored_time = result_times.pop_front();
                wb_valid[out_lane] <= 1;
                wb_data[out_lane*RESULT_W +: RESULT_W] <= result_entry;
                if ((result_tag[0 +: 32] == 16) || (result_tag[0 +: 32] == 32) || (result_tag[0 +: 32] == 36)) begin
                    branch_result_valid <= 1;
                    case (result_tag[0 +: 32])
                        16: branch_result_data <= {32'd32, result_tag};
                        32: branch_result_data <= {32'd36, result_tag};
                        36: branch_result_data <= {32'd48, result_tag};
                        default: begin end
                    endcase
                end
                out_lane++; completed++;
            end
        end
    end

    initial begin
        repeat (3) @(negedge clk);
        reset_n = 1;
        for (int t = 0; t < 5000; t++) begin
            @(negedge clk);
            if (completed >= TARGET) begin
                $display("PASS scheduler flow D=%0d WINDOWS=%0d RANGE=%0d WRITES=%0d issued=%0d", DECODE, WINDOWS, RANGE, WRITES, issued);
                $finish;
            end
        end
        $fatal(1, "Scheduler flow stalled issued=%0d completed=%0d expected_pc=%0d", issued, completed, expected_pc);
    end
endmodule
