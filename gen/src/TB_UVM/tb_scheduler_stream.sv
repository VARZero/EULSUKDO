`timescale 1ns/1ps
module tb_scheduler_stream;
    localparam int INST_COUNT = 160;

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
    logic [9:0] i_nel_decode_microop = 10'd1;
    logic [9:0] i_nel_decode_rd = 10'd1;
    logic [1:0] i_nel_decode_newreg = 2'b01;
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

    logic [34:0] fetch_tag [0:INST_COUNT-1];
    logic [34:0] issue_tag [0:INST_COUNT-1];
    logic [5:0] issue_rd [0:INST_COUNT-1];
    int fetch_ready [0:INST_COUNT-1];
    int result_ready [0:INST_COUNT-1];
    int requested = 0;
    int received = 0;
    int issued = 0;
    int completed = 0;
    int retired = 0;
    logic [63:0] live_phyreg = 0;
    int returned_phyreg;

    initial begin
        repeat (2) @(negedge clk);
        reset_n = 1;
        for (int cycle = 0; cycle < 2500; cycle++) begin
            @(negedge clk);
            i_rs_entry_get = (cycle >= 120) ? 5'b11111 : 0;
            i_im_req_pc_get = (requested < INST_COUNT) ? 2'b01 : 0;
            i_im_recv_inst_valid = (received < requested && cycle >= fetch_ready[received]) ? 2'b01 : 0;
            i_im_recv_pc = (received < requested) ? {35'd0,fetch_tag[received]} : 0;
            i_wbc_result_valid = (completed < issued && cycle >= result_ready[completed]) ? 5'b00001 : 0;
            i_wbc_result_data = (completed < issued) ?
                {164'd0,issue_rd[completed],issue_tag[completed]} : 0;
            #1;
            @(posedge clk);
            if (cycle < 120 && o_rs_entry_valid[0] && o_rs_entry_data[34:0] !== fetch_tag[0])
                $fatal(1, "blocked RS lost its oldest instruction");
            if (o_im_req_pc_valid[0] && i_im_req_pc_get[0]) begin
                if (requested >= INST_COUNT || o_im_req_pc[31:0] !== 32'(requested*4))
                    $fatal(1, "fetch PC lost order at request %0d", requested);
                fetch_tag[requested] = o_im_req_pc[34:0];
                fetch_ready[requested] = cycle + 2 + ((requested*7)%5);
                requested++;
            end
            if (i_im_recv_inst_valid[0] && o_im_recv_inst_get[0]) received++;
            if (o_rs_entry_valid[0] && i_rs_entry_get[0]) begin
                if (issued >= received || issued >= INST_COUNT ||
                    o_rs_entry_data[34:0] !== fetch_tag[issued] ||
                    o_rs_entry_data[79:74] == 0)
                    $fatal(1, "issue tag/physical register at instruction %0d: received=%0d got_tag=%h expected=%h rd=%0d",
                        issued, received, o_rs_entry_data[34:0], fetch_tag[issued], o_rs_entry_data[79:74]);
                if (live_phyreg[o_rs_entry_data[79:74]])
                    $fatal(1, "physical register reused before retirement at instruction %0d", issued);
                live_phyreg[o_rs_entry_data[79:74]] = 1'b1;
                issue_tag[issued] = o_rs_entry_data[34:0];
                issue_rd[issued] = o_rs_entry_data[79:74];
                result_ready[issued] = cycle + 1 + ((issued*3)%6);
                issued++;
            end
            if (i_wbc_result_valid[0]) completed++;
            for (int lane = 0; lane < 4; lane++) begin
                if (dut.fcl_prm_unallocate_phyreg_valid[lane]) begin
                    returned_phyreg = int'(dut.fcl_prm_unallocate_phyreg_data[lane*6 +: 6]);
                    if (returned_phyreg == 0 || !live_phyreg[returned_phyreg])
                        $fatal(1, "unallocated physical register returned twice or before issue");
                    live_phyreg[returned_phyreg] = 1'b0;
                    retired++;
                end
            end
            if (completed == INST_COUNT) begin
                if (requested != INST_COUNT || received != INST_COUNT || issued != INST_COUNT || retired < 80)
                    $fatal(1, "stream accounting requests=%0d recv=%0d issue=%0d done=%0d retired=%0d",
                        requested, received, issued, completed, retired);
                $display("160-instruction stalled multi-flow scheduler stream passed (retired=%0d)", retired);
                $finish;
            end
        end
        if (completed != INST_COUNT)
            $fatal(1, "scheduler stream stalled requests=%0d recv=%0d issue=%0d done=%0d retired=%0d",
                requested, received, issued, completed, retired);
    end
endmodule
