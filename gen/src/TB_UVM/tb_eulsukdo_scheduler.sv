`timescale 1ns/1ps
module tb_eulsukdo_scheduler;
`ifdef GEN_TRACE
    initial begin
        $dumpfile("gen_sample.vcd");
        $dumpvars(0, tb_eulsukdo_scheduler);
    end
`endif
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [1:0] i_im_req_pc_get = 0;
    wire [1:0] o_im_req_pc_valid;
    wire [69:0] o_im_req_pc;
    logic [1:0] i_im_recv_inst_valid = 0;
    wire [1:0] o_im_recv_inst_get;
    logic [69:0] i_im_recv_pc = 0;
    logic [63:0] i_im_recv_inst = 0;
    logic [1:0] i_nel_decode_exception = 0;
    logic [3:0] i_nel_decode_expath = 0;
    logic [9:0] i_nel_decode_microop = 0;
    logic [9:0] i_nel_decode_rd = 0;
    logic [1:0] i_nel_decode_newreg = 0;
    logic [19:0] i_nel_decode_rs = 0;
    logic [63:0] i_nel_decode_imm = 0;
    logic [1:0] i_nel_decode_jump = 0;
    logic [1:0] i_nel_decode_jump_reg = 0;
    logic [1:0] i_nel_decode_branch = 0;
    wire [4:0] o_rs_entry_valid;
    logic [4:0] i_rs_entry_get = 5'b11111;
    wire [459:0] o_rs_entry_data;
    logic [4:0] i_wbc_result_valid = 0;
    logic [204:0] i_wbc_result_data = 0;
    logic i_wbc_result_branch_valid = 0;
    logic [34:0] i_wbc_result_branch_data = 0;
    logic branch_issued = 0;
    logic stale_requested = 0;
    logic response_accepted = 0;
    logic test_passed = 0;
    logic [5:0] allocated_rd = 0;

    eulsukdo_scheduler dut (.*);
    always @(posedge clk) begin
        if (reset_n && o_im_req_pc_valid[0] && i_im_req_pc_get[0] &&
            o_im_req_pc[31:0] == 32'd8)
            stale_requested <= 1'b1;
        if (reset_n && (|o_rs_entry_valid) && o_rs_entry_data[31:0] == 32'd8)
            $fatal(1, "stale instruction reached execution queue: requested=%b discard=%b flow_discard=%b pending0=%0d",
                stale_requested, dut.fcl_im_recv_discard, dut.U_FLOW_CONTROL_LOGIC.flow_discard,
                dut.U_FLOW_CONTROL_LOGIC.flow_pending[0]);
        if (reset_n && (|o_rs_entry_valid) && o_rs_entry_data[31:0] == 32'd4) begin
            if (o_rs_entry_data[85:80] !== allocated_rd)
                $fatal(1, "source did not use renamed physical register");
            branch_issued <= 1'b1;
        end
    end

    initial begin
        @(posedge clk);
        #1;
        reset_n = 1;
        #1;
        if (!o_im_req_pc_valid[0] || o_im_req_pc[34:0] !== 35'd0)
            $fatal(1, "initial fetch request");
        i_im_req_pc_get = 2'b01;
        @(posedge clk);
        #1;
        i_im_req_pc_get = 0;
        i_im_recv_inst_valid = 2'b01;
        i_im_recv_pc = 0;
        i_nel_decode_microop[4:0] = 5'd1;
        i_nel_decode_newreg[0] = 1'b1;
        i_nel_decode_rd[4:0] = 5'd1;
        response_accepted = 0;
        for (int ready_wait = 0; ready_wait < 100; ready_wait++) begin
            @(posedge clk);
            if (o_im_recv_inst_get[0]) begin
                response_accepted = 1;
                break;
            end
        end
        if (!response_accepted) $fatal(1, "decode did not accept instruction");
        #1;
        i_im_recv_inst_valid = 0;
        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            #1;
            if (|o_rs_entry_valid) begin
                if (o_rs_entry_data[34:0] !== 35'd0)
                    $fatal(1, "issue PC tag mismatch");
                i_wbc_result_valid = 5'b00001;
                if (o_rs_entry_data[79:74] == 0) $fatal(1, "physical register was not allocated");
                allocated_rd = o_rs_entry_data[79:74];
                i_wbc_result_data = {164'd0,o_rs_entry_data[79:74],35'd0};
                @(posedge clk);
                #1;
                i_wbc_result_valid = 0;
                if (o_im_req_pc[31:0] !== 32'd4) $fatal(1, "second fetch PC");
                i_im_req_pc_get = 2'b01;
                @(posedge clk);
                #1;
                i_im_req_pc_get = 0;
                i_im_recv_inst_valid = 2'b01;
                i_im_recv_pc = {35'd0,35'd4};
                i_nel_decode_newreg = 0;
                i_nel_decode_rd = 0;
                i_nel_decode_rs[4:0] = 5'd1;
                i_nel_decode_branch = 2'b01;
                if (o_im_req_pc[31:0] !== 32'd8) $fatal(1, "outstanding sequential request PC");
                i_im_req_pc_get = o_im_req_pc_valid[0] ? 2'b01 : 2'b00;
                response_accepted = 0;
                for (int ready_wait = 0; ready_wait < 100; ready_wait++) begin
                    @(posedge clk);
                    if (o_im_recv_inst_get[0]) response_accepted = 1;
                    #1;
                    i_im_req_pc_get = 0;
                    if (response_accepted) break;
                end
                if (!response_accepted) $fatal(1, "branch decode did not accept instruction");
                i_im_recv_inst_valid = 0;
                for (int wait_cycle = 0; wait_cycle < 30; wait_cycle++) begin
                    @(posedge clk);
                    #1;
                    if (!o_im_req_pc_valid[0]) break;
                end
                if (o_im_req_pc_valid[0]) $fatal(1, "branch did not suspend fetch");
                if (!branch_issued) begin
                    for (int issue_wait = 0; issue_wait < 60; issue_wait++) begin
                        @(posedge clk);
                        #1;
                        if (branch_issued) break;
                    end
                end
                if (!branch_issued) $fatal(1, "branch dependent on rd1 did not issue");
                i_wbc_result_branch_valid = 1;
                i_wbc_result_branch_data = {3'b001,32'd64};
                i_wbc_result_valid = 5'b00001;
                i_wbc_result_data = {164'd0,41'd4};
                @(posedge clk);
                #1;
                i_wbc_result_branch_valid = 0;
                i_wbc_result_valid = 0;
                @(posedge clk);
                #1;
                if (!o_im_req_pc_valid[0] || o_im_req_pc[31:0] !== 32'd64 ||
                    o_im_req_pc[34:32] == 3'd0)
                    $fatal(1, "branch resolution did not redirect fetch");
                if (stale_requested) begin
                    i_im_recv_inst_valid = 2'b01;
                    i_im_recv_pc = {35'd0,35'd8};
                    #1;
                    if (!o_im_recv_inst_get[0]) $fatal(1, "stale branch-path IM response not discarded");
                    @(posedge clk);
                    #1;
                    i_im_recv_inst_valid = 0;
                end
                repeat (5) @(posedge clk);
                $display("scheduler decode-to-issue-to-writeback, branch redirect and stale IM response passed");
                test_passed = 1;
                $finish;
            end
        end
        if (!test_passed) $fatal(1, "decoded instruction was never issued");
    end
endmodule
