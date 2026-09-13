`timescale 1ns/1ps

module tb_eulsukdo_ipc #(
    parameter int P_DECODE_WIDTH = 2,
    parameter int P_ISSUE_ALU = 1,
    parameter int P_ISSUE_SLOW = 1,
    parameter int P_INSTRUCTIONS = 240,
    parameter int P_SLOW_LATENCY = 4
);
    localparam int PC_WIDTH = 16;
    localparam int LOG_REGS = 16;
    localparam int OPERANDS = 2;
    localparam int IMM_WIDTH = 12;
    localparam int MICROOP_WIDTH = 4;
    localparam int IST_ENTRIES = 64;
    localparam int PHY_REGS = 96;
    localparam int EX_PATHS = 2;
    localparam int FLOW_WINDOWS = 4;
    localparam int ISSUE_PORTS = P_ISSUE_ALU + P_ISSUE_SLOW;
    localparam int RESULT_PORTS = ISSUE_PORTS;
    localparam int WAKE_PORTS = ISSUE_PORTS * 2;
    localparam int FREE_PORTS = (P_DECODE_WIDTH > ISSUE_PORTS) ? P_DECODE_WIDTH : ISSUE_PORTS;
    localparam int LOG_REG_WIDTH = $clog2(LOG_REGS);
    localparam int PHY_REG_WIDTH = $clog2(PHY_REGS);
    localparam int EX_PATH_WIDTH = $clog2(EX_PATHS);
    localparam int FLOW_WIDTH = $clog2(FLOW_WINDOWS);
    localparam int FETCH_WIDTH = PC_WIDTH + FLOW_WIDTH;
    localparam int ISSUE_WIDTH = PC_WIDTH + FLOW_WIDTH + MICROOP_WIDTH + IMM_WIDTH +
                                 PHY_REG_WIDTH + OPERANDS*PHY_REG_WIDTH;
    localparam int RESULT_WIDTH = PC_WIDTH + FLOW_WIDTH + PHY_REG_WIDTH;
    localparam int BRANCH_WIDTH = PC_WIDTH + FLOW_WIDTH + 1 + PC_WIDTH;
    localparam int ISSUE_P_RD = PC_WIDTH + FLOW_WIDTH + MICROOP_WIDTH + IMM_WIDTH;
    localparam int MAX_LATENCY = (P_SLOW_LATENCY > 1) ? P_SLOW_LATENCY : 1;

    logic clk;
    logic reset_n;
    logic [P_DECODE_WIDTH-1:0] fetch_valid;
    logic [P_DECODE_WIDTH-1:0] fetch_get;
    logic [P_DECODE_WIDTH*FETCH_WIDTH-1:0] fetch_data;
    logic [P_DECODE_WIDTH-1:0] decode_valid;
    logic [P_DECODE_WIDTH-1:0] decode_get;
    logic [P_DECODE_WIDTH*PC_WIDTH-1:0] decode_pc;
    logic [P_DECODE_WIDTH*FLOW_WIDTH-1:0] decode_flow;
    logic [P_DECODE_WIDTH*EX_PATH_WIDTH-1:0] decode_path;
    logic [P_DECODE_WIDTH*MICROOP_WIDTH-1:0] decode_uop;
    logic [P_DECODE_WIDTH*IMM_WIDTH-1:0] decode_imm;
    logic [P_DECODE_WIDTH*LOG_REG_WIDTH-1:0] decode_rd;
    logic [P_DECODE_WIDTH-1:0] decode_writes_rd;
    logic [P_DECODE_WIDTH*OPERANDS*LOG_REG_WIDTH-1:0] decode_rs;
    logic [P_DECODE_WIDTH-1:0] decode_exception;
    logic [P_DECODE_WIDTH-1:0] decode_jump;
    logic [P_DECODE_WIDTH-1:0] decode_jump_reg;
    logic [P_DECODE_WIDTH-1:0] decode_branch;
    logic [P_DECODE_WIDTH*PC_WIDTH-1:0] decode_target_pc;
    logic [ISSUE_PORTS-1:0] issue_valid;
    logic [ISSUE_PORTS-1:0] issue_get;
    logic [ISSUE_PORTS*ISSUE_WIDTH-1:0] issue_data;
    logic [RESULT_PORTS-1:0] result_valid;
    logic [RESULT_PORTS*RESULT_WIDTH-1:0] result_data;
    logic branch_valid;
    logic [BRANCH_WIDTH-1:0] branch_data;

    logic pipe_valid [0:RESULT_PORTS-1][0:MAX_LATENCY-1];
    logic [RESULT_WIDTH-1:0] pipe_data [0:RESULT_PORTS-1][0:MAX_LATENCY-1];
    integer cycle_count;
    integer completed_count;
    integer retired_count;
    integer workload_kind;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    eulsukdo_gen3 #(
        .PC_WIDTH(PC_WIDTH), .PC_STEP(4), .LOG_REGS(LOG_REGS), .OPERANDS(OPERANDS),
        .IMM_WIDTH(IMM_WIDTH), .MICROOP_WIDTH(MICROOP_WIDTH),
        .DECODE_WIDTH(P_DECODE_WIDTH), .IST_ENTRIES(IST_ENTRIES), .PHY_REGS(PHY_REGS),
        .EX_PATHS(EX_PATHS), .FLOW_WINDOWS(FLOW_WINDOWS), .RESULT_PORTS(RESULT_PORTS),
        .BRANCH_PORTS(1), .DEPTH_PER_REG(8), .WAKE_PORTS(WAKE_PORTS),
        .FREE_PORTS(FREE_PORTS), .RS_DEPTH(32), .ISSUE_PORTS(ISSUE_PORTS),
        .ISSUE_PER_PATH({8'(P_ISSUE_SLOW), 8'(P_ISSUE_ALU)}), .ROB_ENTRIES(IST_ENTRIES)
    ) dut (
        .clk, .reset_n,
        .o_fetch_valid(fetch_valid), .i_fetch_get(fetch_get), .o_fetch_data(fetch_data),
        .i_decode_valid(decode_valid), .o_decode_get(decode_get), .i_decode_pc(decode_pc),
        .i_decode_flow(decode_flow), .i_decode_ex_path(decode_path),
        .i_decode_microop(decode_uop), .i_decode_imm(decode_imm), .i_decode_rd(decode_rd),
        .i_decode_writes_rd(decode_writes_rd), .i_decode_rs(decode_rs),
        .i_decode_exception(decode_exception), .i_decode_jump(decode_jump),
        .i_decode_jump_reg(decode_jump_reg), .i_decode_branch(decode_branch),
        .i_decode_target_pc(decode_target_pc), .o_issue_valid(issue_valid),
        .i_issue_get(issue_get), .o_issue_data(issue_data),
        .i_result_valid(result_valid), .i_result_data(result_data),
        .i_branch_valid(branch_valid), .i_branch_data(branch_data)
    );

    always_comb begin
        result_valid = '0;
        result_data = '0;
        for (integer result_port = 0; result_port < RESULT_PORTS; result_port++) begin
            result_valid[result_port] = pipe_valid[result_port][0];
            result_data[result_port*RESULT_WIDTH +: RESULT_WIDTH] = pipe_data[result_port][0];
        end
    end

    always_ff @(posedge clk) begin : execution_model
        integer latency;
        logic [ISSUE_WIDTH-1:0] issued;
        logic [RESULT_WIDTH-1:0] completion;
        if (!reset_n) begin
            for (integer port = 0; port < RESULT_PORTS; port++) begin
                for (integer stage = 0; stage < MAX_LATENCY; stage++) begin
                    pipe_valid[port][stage] <= 1'b0;
                    pipe_data[port][stage] <= '0;
                end
            end
        end else begin
            for (integer port = 0; port < RESULT_PORTS; port++) begin
                for (integer stage = 0; stage < MAX_LATENCY-1; stage++) begin
                    pipe_valid[port][stage] <= pipe_valid[port][stage+1];
                    pipe_data[port][stage] <= pipe_data[port][stage+1];
                end
                pipe_valid[port][MAX_LATENCY-1] <= 1'b0;
                pipe_data[port][MAX_LATENCY-1] <= '0;

                if (issue_valid[port] && issue_get[port]) begin
                    latency = (port < P_ISSUE_ALU) ? 1 : P_SLOW_LATENCY;
                    issued = issue_data[port*ISSUE_WIDTH +: ISSUE_WIDTH];
                    completion = '0;
                    completion[0 +: PC_WIDTH] = issued[0 +: PC_WIDTH];
                    completion[PC_WIDTH +: FLOW_WIDTH] = issued[PC_WIDTH +: FLOW_WIDTH];
                    completion[PC_WIDTH+FLOW_WIDTH +: PHY_REG_WIDTH] =
                        issued[ISSUE_P_RD +: PHY_REG_WIDTH];
                    pipe_valid[port][latency-1] <= 1'b1;
                    pipe_data[port][latency-1] <= completion;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            cycle_count <= 0;
            completed_count <= 0;
            retired_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            completed_count <= completed_count + $countones(result_valid);
            retired_count <= retired_count + dut.u_fcl.retire_count;
        end
    end

    task automatic clear_decode;
        begin
            decode_valid = '0;
            decode_pc = '0;
            decode_flow = '0;
            decode_path = '0;
            decode_uop = '0;
            decode_imm = '0;
            decode_rd = '0;
            decode_writes_rd = '0;
            decode_rs = '0;
            decode_exception = '0;
            decode_jump = '0;
            decode_jump_reg = '0;
            decode_branch = '0;
            decode_target_pc = '0;
        end
    endtask

    task automatic make_instruction(input integer lane, input integer id, input integer kind);
        integer rd;
        integer rs;
        integer path;
        begin
            rd = (id % (LOG_REGS-1)) + 1;
            rs = 0;
            path = id % 2;
            case (kind)
                0: begin // Independent, balanced across both paths.
                    rs = 0;
                    path = id % 2;
                end
                1: begin // One long RAW chain, alternating fast/slow execution.
                    rd = 1;
                    rs = (id == 0) ? 0 : 1;
                    path = id % 2;
                end
                2: begin // Two-instruction chains, 75% ALU / 25% slow-path mix.
                    path = ((id % 4) == 3) ? 1 : 0;
                    if ((id % 2) == 1) rs = ((id-1) % (LOG_REGS-1)) + 1;
                end
                3: begin // Independent but all contend for the slow path.
                    rs = 0;
                    path = 1;
                end
                default: begin // One long RAW chain using only the 1-cycle ALU.
                    rd = 1;
                    rs = (id == 0) ? 0 : 1;
                    path = 0;
                end
            endcase
            decode_valid[lane] = 1'b1;
            decode_pc[lane*PC_WIDTH +: PC_WIDTH] = PC_WIDTH'(id*4);
            decode_path[lane*EX_PATH_WIDTH +: EX_PATH_WIDTH] = EX_PATH_WIDTH'(path);
            decode_uop[lane*MICROOP_WIDTH +: MICROOP_WIDTH] = MICROOP_WIDTH'(path+1);
            decode_rd[lane*LOG_REG_WIDTH +: LOG_REG_WIDTH] = LOG_REG_WIDTH'(rd);
            decode_writes_rd[lane] = 1'b1;
            decode_rs[(lane*OPERANDS+0)*LOG_REG_WIDTH +: LOG_REG_WIDTH] = LOG_REG_WIDTH'(rs);
            decode_rs[(lane*OPERANDS+1)*LOG_REG_WIDTH +: LOG_REG_WIDTH] = '0;
        end
    endtask

    task automatic run_workload(input integer kind);
        integer sent;
        integer lanes;
        integer start_cycle;
        integer measured_cycles;
        real ipc;
        string name;
        begin
            workload_kind = kind;
            clear_decode();
            reset_n = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset_n = 1'b1;
            sent = 0;
            start_cycle = -1;

            while (sent < P_INSTRUCTIONS) begin
                @(negedge clk);
                clear_decode();
                lanes = 0;
                for (integer lane = 0; lane < P_DECODE_WIDTH; lane++) begin
                    if ((sent + lane) < P_INSTRUCTIONS) begin
                        make_instruction(lane, sent + lane, kind);
                        lanes++;
                    end
                end
                do @(posedge clk); while ((decode_get & decode_valid) != decode_valid);
                if (start_cycle < 0) start_cycle = cycle_count;
                sent += lanes;
            end
            @(negedge clk);
            clear_decode();

            while (retired_count < P_INSTRUCTIONS) begin
                @(posedge clk);
                if ((cycle_count - start_cycle) > 20000)
                    $fatal(1, "IPC workload %0d timed out at %0d completions / %0d retirements",
                           kind, completed_count, retired_count);
            end
            measured_cycles = cycle_count - start_cycle + 1;
            ipc = $itor(P_INSTRUCTIONS) / $itor(measured_cycles);
            case (kind)
                0: name = "independent_balanced";
                1: name = "serial_raw_chain";
                2: name = "mixed_pair_chains";
                3: name = "slow_path_pressure";
                default: name = "alu_raw_chain";
            endcase
            $display("IPC_RESULT,%0d,%0d,%0d,%s,%0d,%0d,%0.6f",
                     P_DECODE_WIDTH, P_ISSUE_ALU, P_ISSUE_SLOW, name,
                     P_INSTRUCTIONS, measured_cycles, ipc);
            @(negedge clk);
        end
    endtask

    initial begin
        reset_n = 1'b0;
        fetch_get = '0;
        issue_get = '1;
        branch_valid = 1'b0;
        branch_data = '0;
        clear_decode();
        run_workload(0);
        run_workload(1);
        run_workload(2);
        run_workload(3);
        run_workload(4);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "global IPC benchmark timeout");
    end
endmodule
