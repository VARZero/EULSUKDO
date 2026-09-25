`timescale 1ns/1ps
module tb_scheduler_two_lane;
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

    eulsukdo_scheduler dut (.*);
    logic [5:0] first_rd;
    logic seen_first = 0;
    logic seen_second = 0;
    logic seen_third = 0;
    logic [5:0] repeated_first_rd;
    logic [5:0] repeated_last_rd;
    logic repeated_first_issued = 0;
    logic repeated_last_issued = 0;
    logic final_reader_issued = 0;

    task automatic accept_response(input logic [1:0] lanes);
        bit accepted;
        accepted = 0;
        for (int wait_cycle = 0; wait_cycle < 100; wait_cycle++) begin
            @(posedge clk);
            if ((o_im_recv_inst_get & lanes) == lanes) begin
                accepted = 1;
                break;
            end
        end
        if (!accepted) $fatal(1, "decode acceptance timeout for lanes %b", lanes);
        #1;
        i_im_recv_inst_valid = 0;
    endtask

    initial begin
        @(posedge clk);
        #1;
        reset_n = 1;
        i_im_req_pc_get = 2'b11;
        #1;
        if (o_im_req_pc_valid !== 2'b11 ||
            o_im_req_pc[34:0] !== 35'd0 || o_im_req_pc[69:35] !== 35'd4)
            $fatal(1, "two-lane fetch requests");
        @(posedge clk);
        #1;
        i_im_req_pc_get = 0;
        i_im_recv_inst_valid = 2'b11;
        i_im_recv_pc = {35'd4,35'd0};
        i_nel_decode_microop = {5'd1,5'd1};
        i_nel_decode_rd = {5'd2,5'd1};
        i_nel_decode_newreg = 2'b11;
        i_nel_decode_rs[14:10] = 5'd1;
        accept_response(2'b11);
        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            #1;
            if (o_rs_entry_valid[0] && o_rs_entry_data[31:0] == 32'd0 && !seen_first) begin
                first_rd = o_rs_entry_data[79:74];
                if (first_rd == 0) $fatal(1, "first lane lacks physical destination");
                seen_first = 1;
                i_wbc_result_valid[0] = 1;
                i_wbc_result_data = {164'd0,first_rd,35'd0};
                #1;
                if (dut.wbc_broadcast_done_phyreg_data[5:0] !== first_rd)
                    $fatal(1, "write-back physical register mismatch");
            end
            else if (seen_first && i_wbc_result_valid[0]) begin
                i_wbc_result_valid = 0;
            end
            if (o_rs_entry_valid[0] && o_rs_entry_data[31:0] == 32'd4) begin
                if (!seen_first) $fatal(1, "dependent lane issued before producer");
                if (o_rs_entry_data[85:80] !== first_rd || o_rs_entry_data[79:74] == first_rd ||
                    o_rs_entry_data[79:74] == 0)
                    $fatal(1, "second lane physical-register rename");
                seen_second = 1;
                break;
            end
        end
        if (!seen_second) $fatal(1, "dependent lane never issued");
        i_im_req_pc_get = 2'b01;
        #1;
        if (o_im_req_pc[31:0] !== 32'd8) $fatal(1, "third fetch PC");
        @(posedge clk);
        #1;
        i_im_req_pc_get = 0;
        i_im_recv_inst_valid = 2'b01;
        i_im_recv_pc = {35'd0,35'd8};
        i_nel_decode_newreg = 0;
        i_nel_decode_rs = 20'd1;
        accept_response(2'b01);
        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            #1;
            if (o_rs_entry_valid[0] && o_rs_entry_data[31:0] == 32'd8) begin
                if (o_rs_entry_data[85:80] !== first_rd)
                    $fatal(1, "first lane architectural mapping was lost");
                seen_third = 1;
                break;
            end
        end
        if (!seen_third) $fatal(1, "third instruction never issued");

        // Two writes to the same architectural register in one bundle:
        // the later writer reads the earlier PRD, then becomes the mapping.
        i_im_req_pc_get = 2'b11;
        #1;
        if (o_im_req_pc[34:0] !== 35'd12 || o_im_req_pc[69:35] !== 35'd16)
            $fatal(1, "repeated-destination request pair");
        @(posedge clk);
        #1;
        i_im_req_pc_get = 0;
        i_im_recv_inst_valid = 2'b11;
        i_im_recv_pc = {35'd16,35'd12};
        i_nel_decode_newreg = 2'b11;
        i_nel_decode_rd = {5'd1,5'd1};
        i_nel_decode_rs = 20'(1 << 10);
        accept_response(2'b11);
        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            #1;
            if (o_rs_entry_valid[0] && o_rs_entry_data[31:0] == 32'd12 && !repeated_first_issued) begin
                repeated_first_rd = o_rs_entry_data[79:74];
                if (repeated_first_rd == 0 || repeated_first_rd == first_rd)
                    $fatal(1, "earlier repeated destination not renamed");
                repeated_first_issued = 1;
                i_wbc_result_valid = 5'b00001;
                i_wbc_result_data = {164'd0,repeated_first_rd,35'd12};
            end
            else if (repeated_first_issued && i_wbc_result_valid[0])
                i_wbc_result_valid = 0;
            if (o_rs_entry_valid[0] && o_rs_entry_data[31:0] == 32'd16) begin
                repeated_last_rd = o_rs_entry_data[79:74];
                if (o_rs_entry_data[85:80] !== repeated_first_rd ||
                    repeated_last_rd == 0 || repeated_last_rd == repeated_first_rd)
                    $fatal(1, "same-destination bypass/second allocation");
                repeated_last_issued = 1;
                break;
            end
        end
        if (!repeated_last_issued) $fatal(1, "dependent same-destination writer never issued");
        i_wbc_result_valid = 5'b00001;
        i_wbc_result_data = {164'd0,repeated_last_rd,35'd16};
        @(posedge clk);
        #1;
        i_wbc_result_valid = 0;
        i_im_req_pc_get = 2'b01;
        #1;
        if (o_im_req_pc[31:0] !== 32'd20) $fatal(1, "post-bundle request PC");
        @(posedge clk);
        #1;
        i_im_req_pc_get = 0;
        i_im_recv_inst_valid = 2'b01;
        i_im_recv_pc = {35'd0,35'd20};
        i_nel_decode_newreg = 0;
        i_nel_decode_rs = 20'd1;
        accept_response(2'b01);
        for (int cycle = 0; cycle < 100; cycle++) begin
            @(posedge clk);
            #1;
            if (o_rs_entry_valid[0] && o_rs_entry_data[31:0] == 32'd20) begin
                if (o_rs_entry_data[85:80] !== repeated_last_rd)
                    $fatal(1, "youngest writer did not update architectural mapping");
                $display("two-lane rename, wakeup and repeated destination passed");
                final_reader_issued = 1;
                $finish;
            end
        end
        if (!final_reader_issued) $fatal(1, "post-bundle reader never issued");
    end
endmodule
