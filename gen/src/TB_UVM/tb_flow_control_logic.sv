`timescale 1ns/1ps
module tb_flow_control_logic;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic [4:0] done_valid = 0;
    logic [174:0] done_pc = 0;
    logic branch_valid = 0;
    logic [34:0] branch_data = 0;
    logic jump_valid = 0;
    logic [34:0] jump_data = 0;
    logic [1:0] retired_valid = 0;
    logic [81:0] retired_data = 0;
    logic [1:0] im_valid = 0;
    logic [1:0] im_get = 0;
    logic [69:0] im_pc = 0;
    wire [1:0] im_discard;
    logic [1:0] req_get = 0;
    wire [1:0] req_valid;
    wire [69:0] req_pc;
    wire [3:0] unalloc_valid;
    wire [23:0] unalloc_data;
    logic [2:0] rolled_flow;

    flow_control_logic dut (
        .clk(clk), .reset_n(reset_n),
        .i_wbc_done_pc_valid(done_valid), .i_wbc_done_pc_data(done_pc),
        .i_wbc_branch_valid(branch_valid), .i_wbc_branch_data(branch_data),
        .i_nel_jumpbranch_valid(jump_valid), .i_nel_jumpbranch_data(jump_data),
        .i_nel_retired_phyreg_valid(retired_valid), .i_nel_retired_phyreg_data(retired_data),
        .i_im_recv_inst_valid(im_valid), .i_im_recv_inst_get(im_get),
        .i_im_recv_pc(im_pc), .o_im_recv_discard(im_discard),
        .o_im_req_pc_valid(req_valid), .i_im_req_pc_get(req_get), .o_im_req_pc(req_pc),
        .o_prm_unallocate_phyreg_valid(unalloc_valid),
        .o_prm_unallocate_phyreg_data(unalloc_data)
    );

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    initial begin
        tick();
        reset_n = 1;
        #1;
        if (req_pc[34:0] !== 35'd0) $fatal(1, "reset PC");
        req_get = 2'b11;
        tick();
        req_get = 0;
        #1;
        if (req_pc[34:0] !== 35'd8) $fatal(1, "request progression");

        // Flow 0 admits two instructions. The second replaces physical register 7.
        // A jump closes this flow and starts flow 1 at PC 100.
        im_valid = 2'b11;
        im_get = 2'b11;
        im_pc = {35'd4, 35'd0};
        retired_valid = 2'b10;
        retired_data = {6'd7, 35'd4, 41'd0};
        jump_valid = 1;
        jump_data = {1'b1, 2'b00, 32'd100};
        #1;
        if (|unalloc_valid) $fatal(1, "early unallocate on admission");
        tick();
        im_valid = 0;
        im_get = 0;
        retired_valid = 0;
        jump_valid = 0;
        #1;
        if (req_pc[34:0] !== {3'd1,32'd100}) $fatal(1, "jump PC/flow");

        // Completing the replacing instruction alone cannot free the old register.
        done_valid = 1;
        done_pc = {140'd0,35'd4};
        tick();
        done_valid = 0;
        #1;
        if (|unalloc_valid) $fatal(1, "freed before older instruction completed");
        done_valid = 1;
        done_pc = '0;
        #1;
        if (unalloc_valid !== 4'b0001 || unalloc_data[5:0] !== 6'd7)
            $fatal(1, "missing deferred retirement: valid=%b data=%d", unalloc_valid, unalloc_data[5:0]);
        tick();
        done_valid = 0;
        #1;
        if (|unalloc_valid) $fatal(1, "duplicate unallocate");

        // Sixteen sequential requests must roll into a fresh flow even
        // without a control-flow instruction.
        for (int n = 0; n < 16; n++) begin
            #1;
            if (req_valid[0] !== 1'b1 || req_pc[31:0] !== 32'(100+4*n) ||
                req_pc[34:32] !== 3'd1) $fatal(1, "window request %0d", n);
            req_get = 2'b01;
            tick();
            req_get = 0;
        end
        #1;
        rolled_flow = req_pc[34:32];
        if (rolled_flow == 3'd1 || req_pc[31:0] !== 32'd164)
            $fatal(1, "sequential flow rollover");
        req_get = 2'b01;
        tick();
        req_get = 0;
        jump_valid = 1;
        jump_data = {1'b1,2'b00,32'd200};
        tick();
        jump_valid = 0;
        im_valid = 2'b01;
        im_get = 2'b01;
        im_pc = {35'd0,{rolled_flow,32'd164}};
        #1;
        if (im_discard[0] !== 1'b1) $fatal(1, "stale IM response was admitted");
        tick();
        im_valid = 0;
        im_get = 0;

        // A sequential flow can close while earlier IM requests are still
        // outstanding. A completed writer cannot retire its old register
        // until every requested instruction in that flow has returned.
        reset_n = 0;
        tick();
        reset_n = 1;
        for (int n = 0; n < 16; n++) begin
            req_get = 2'b01;
            tick();
            req_get = 0;
        end
        if (req_pc[34:32] == 3'd0) $fatal(1, "sequential flow did not close");
        im_valid = 2'b01;
        im_get = 2'b01;
        im_pc = '0;
        retired_valid = 2'b01;
        retired_data = {41'd0,6'd7,35'd0};
        tick();
        retired_valid = 0;
        im_valid = 0;
        im_get = 0;
        done_valid = 1;
        done_pc = '0;
        #1;
        if (|unalloc_valid) $fatal(1, "retired before pending IM requests returned");
        tick();
        done_valid = 0;
        #1;
        if (|unalloc_valid) $fatal(1, "retired while pending IM requests remain");
        for (int n = 1; n < 16; n++) begin
            im_valid = 2'b01;
            im_get = 2'b01;
            im_pc = {35'd0,35'(4*n)};
            done_valid = 1;
            done_pc = {140'd0,35'(4*n)};
            #1;
            if (n < 15 && (|unalloc_valid)) $fatal(1, "early retirement at IM response %0d", n);
            if (n == 15 && (unalloc_valid[0] !== 1'b1 || unalloc_data[5:0] !== 6'd7))
                $fatal(1, "missing retirement after last IM response");
            tick();
        end
        im_valid = 0;
        im_get = 0;
        done_valid = 0;
        #1;
        if (|unalloc_valid) $fatal(1, "duplicate retirement after last IM response");
        $display("flow retirement, bounded rollover and stale response discard passed");
        $finish;
    end
endmodule
