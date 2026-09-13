`timescale 1ns/1ps

module eulsukdo_new_entry_logic #(
    parameter int unsigned PC_WIDTH       = 32,
    parameter int unsigned LOG_REGS       = 32,
    parameter int unsigned OPERANDS       = 2,
    parameter int unsigned IMM_WIDTH      = 32,
    parameter int unsigned MICROOP_WIDTH  = 5,
    parameter int unsigned DECODE_WIDTH   = 2,
    parameter int unsigned IST_ENTRIES    = 128,
    parameter int unsigned PHY_REGS       = 64,
    parameter int unsigned EX_PATHS       = 3,
    parameter int unsigned FLOW_WINDOWS   = 8,
    parameter int unsigned RESULT_PORTS   = 5,
    parameter int unsigned LOG_REG_WIDTH  = (LOG_REGS <= 1) ? 1 : $clog2(LOG_REGS),
    parameter int unsigned PHY_REG_WIDTH  = (PHY_REGS <= 1) ? 1 : $clog2(PHY_REGS),
    parameter int unsigned EX_PATH_WIDTH  = (EX_PATHS <= 1) ? 1 : $clog2(EX_PATHS),
    parameter int unsigned FLOW_WIDTH     = (FLOW_WINDOWS <= 1) ? 1 : $clog2(FLOW_WINDOWS),
    parameter int unsigned INTERNAL_WIDTH = PC_WIDTH + FLOW_WIDTH + EX_PATH_WIDTH +
                                            MICROOP_WIDTH + IMM_WIDTH + PHY_REG_WIDTH +
                                            (OPERANDS * PHY_REG_WIDTH) + OPERANDS,
    parameter int unsigned RETIRE_WIDTH   = PC_WIDTH + FLOW_WIDTH + PHY_REG_WIDTH + 1,
    parameter int unsigned CONTROL_WIDTH  = PC_WIDTH + FLOW_WIDTH + PC_WIDTH + 3
) (
    input  logic                              clk,
    input  logic                              reset_n,

    input  logic [DECODE_WIDTH-1:0]           i_dec_valid,
    output logic [DECODE_WIDTH-1:0]           o_dec_get,
    input  logic [DECODE_WIDTH*PC_WIDTH-1:0]  i_dec_pc,
    input  logic [DECODE_WIDTH*FLOW_WIDTH-1:0] i_dec_flow,
    input  logic [DECODE_WIDTH*EX_PATH_WIDTH-1:0] i_dec_ex_path,
    input  logic [DECODE_WIDTH*MICROOP_WIDTH-1:0] i_dec_microop,
    input  logic [DECODE_WIDTH*IMM_WIDTH-1:0] i_dec_imm,
    input  logic [DECODE_WIDTH*LOG_REG_WIDTH-1:0] i_dec_rd,
    input  logic [DECODE_WIDTH-1:0]           i_dec_writes_rd,
    input  logic [DECODE_WIDTH*OPERANDS*LOG_REG_WIDTH-1:0] i_dec_rs,
    input  logic [DECODE_WIDTH-1:0]           i_dec_exception,
    input  logic [DECODE_WIDTH-1:0]           i_dec_jump,
    input  logic [DECODE_WIDTH-1:0]           i_dec_jump_reg,
    input  logic [DECODE_WIDTH-1:0]           i_dec_branch,
    input  logic [DECODE_WIDTH*PC_WIDTH-1:0]  i_dec_target_pc,

    output logic [DECODE_WIDTH-1:0]           o_prm_alloc_req,
    input  logic [DECODE_WIDTH-1:0]           i_prm_alloc_valid,
    input  logic [DECODE_WIDTH*PHY_REG_WIDTH-1:0] i_prm_alloc_phy,
    output logic [DECODE_WIDTH-1:0]           o_prm_alloc_get,

    input  logic [RESULT_PORTS-1:0]           i_done_valid,
    input  logic [RESULT_PORTS*PHY_REG_WIDTH-1:0] i_done_phy,

    output logic [DECODE_WIDTH-1:0]           o_ist_valid,
    input  logic [DECODE_WIDTH-1:0]           i_ist_get,
    output logic [DECODE_WIDTH*INTERNAL_WIDTH-1:0] o_ist_data,

    output logic [DECODE_WIDTH-1:0]           o_fcl_retire_valid,
    output logic [DECODE_WIDTH*RETIRE_WIDTH-1:0] o_fcl_retire_data,
    input  logic                              i_fcl_retire_ready,
    output logic                              o_fcl_control_valid,
    output logic [CONTROL_WIDTH-1:0]          o_fcl_control_data
);
    localparam int unsigned P_PC       = 0;
    localparam int unsigned P_FLOW     = P_PC + PC_WIDTH;
    localparam int unsigned P_PATH     = P_FLOW + FLOW_WIDTH;
    localparam int unsigned P_UOP      = P_PATH + EX_PATH_WIDTH;
    localparam int unsigned P_IMM      = P_UOP + MICROOP_WIDTH;
    localparam int unsigned P_RD       = P_IMM + IMM_WIDTH;
    localparam int unsigned P_RS       = P_RD + PHY_REG_WIDTH;
    localparam int unsigned P_READY    = P_RS + OPERANDS*PHY_REG_WIDTH;

    logic [PHY_REG_WIDTH-1:0] rename_map [0:LOG_REGS-1];
    logic [PHY_REGS-1:0]      phy_ready;
    logic [PHY_REG_WIDTH-1:0] next_map [0:LOG_REGS-1];
    logic [PHY_REGS-1:0]      ready_now;
    logic                     resources_ok;
    logic                     all_consumers_ready;
    logic                     bundle_fire;

    integer lane;
    integer operand;
    integer reg_idx;
    integer done_idx;
    logic [LOG_REG_WIDTH-1:0] logical_rs;
    logic [LOG_REG_WIDTH-1:0] logical_rd;
    logic [PHY_REG_WIDTH-1:0] source_phy;
    logic [PHY_REG_WIDTH-1:0] dest_phy;
    logic [PHY_REG_WIDTH-1:0] old_dest_phy;
    logic                     source_ready;
    logic                     creates_dest;
    logic                     scheduled;
    logic                     control_seen;
    logic [DECODE_WIDTH-1:0]  lane_schedule;
    logic                     control_prefix_open;

    always_comb begin
        lane_schedule = '0;
        control_prefix_open = 1'b1;
        for (integer prefix_lane = 0; prefix_lane < DECODE_WIDTH; prefix_lane = prefix_lane + 1) begin
            lane_schedule[prefix_lane] = i_dec_valid[prefix_lane] &&
                                         !i_dec_exception[prefix_lane] && control_prefix_open;
            if (i_dec_valid[prefix_lane] &&
                (i_dec_jump[prefix_lane] || i_dec_jump_reg[prefix_lane] || i_dec_branch[prefix_lane]))
                control_prefix_open = 1'b0;
        end
    end

    genvar alloc_lane;
    generate
        for (alloc_lane = 0; alloc_lane < DECODE_WIDTH; alloc_lane = alloc_lane + 1) begin : g_alloc_request
            always_comb begin
                o_prm_alloc_req[alloc_lane] = lane_schedule[alloc_lane] && i_dec_writes_rd[alloc_lane] &&
                    (i_dec_rd[alloc_lane*LOG_REG_WIDTH +: LOG_REG_WIDTH] != '0);
            end
        end
    endgenerate

    always_comb begin
        ready_now = phy_ready;
        ready_now[0] = 1'b1;
        for (done_idx = 0; done_idx < RESULT_PORTS; done_idx = done_idx + 1) begin
            if (i_done_valid[done_idx]) begin
                ready_now[i_done_phy[done_idx*PHY_REG_WIDTH +: PHY_REG_WIDTH]] = 1'b1;
            end
        end

        for (reg_idx = 0; reg_idx < LOG_REGS; reg_idx = reg_idx + 1) begin
            next_map[reg_idx] = rename_map[reg_idx];
        end

        resources_ok = i_fcl_retire_ready;
        for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
            logical_rd = i_dec_rd[lane*LOG_REG_WIDTH +: LOG_REG_WIDTH];
            creates_dest = lane_schedule[lane] && i_dec_writes_rd[lane] && (logical_rd != '0);
            if (creates_dest && !i_prm_alloc_valid[lane]) resources_ok = 1'b0;
        end

        all_consumers_ready = 1'b1;
        for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
            scheduled = lane_schedule[lane];
            if (scheduled && !i_ist_get[lane]) all_consumers_ready = 1'b0;
        end
        bundle_fire = resources_ok && all_consumers_ready && (|i_dec_valid);

        o_dec_get            = '0;
        o_prm_alloc_get      = '0;
        o_ist_valid          = '0;
        o_ist_data           = '0;
        o_fcl_retire_valid   = '0;
        o_fcl_retire_data    = '0;
        o_fcl_control_valid  = 1'b0;
        o_fcl_control_data   = '0;
        control_seen         = 1'b0;

        for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
            scheduled = lane_schedule[lane];
            logical_rd = i_dec_rd[lane*LOG_REG_WIDTH +: LOG_REG_WIDTH];
            creates_dest = scheduled && i_dec_writes_rd[lane] && (logical_rd != '0);
            dest_phy = creates_dest ? i_prm_alloc_phy[lane*PHY_REG_WIDTH +: PHY_REG_WIDTH] : '0;
            old_dest_phy = next_map[logical_rd];

            o_ist_valid[lane] = scheduled && resources_ok;
            o_ist_data[lane*INTERNAL_WIDTH + P_PC +: PC_WIDTH] =
                i_dec_pc[lane*PC_WIDTH +: PC_WIDTH];
            o_ist_data[lane*INTERNAL_WIDTH + P_FLOW +: FLOW_WIDTH] =
                i_dec_flow[lane*FLOW_WIDTH +: FLOW_WIDTH];
            o_ist_data[lane*INTERNAL_WIDTH + P_PATH +: EX_PATH_WIDTH] =
                i_dec_ex_path[lane*EX_PATH_WIDTH +: EX_PATH_WIDTH];
            o_ist_data[lane*INTERNAL_WIDTH + P_UOP +: MICROOP_WIDTH] =
                i_dec_microop[lane*MICROOP_WIDTH +: MICROOP_WIDTH];
            o_ist_data[lane*INTERNAL_WIDTH + P_IMM +: IMM_WIDTH] =
                i_dec_imm[lane*IMM_WIDTH +: IMM_WIDTH];
            o_ist_data[lane*INTERNAL_WIDTH + P_RD +: PHY_REG_WIDTH] = dest_phy;

            for (operand = 0; operand < OPERANDS; operand = operand + 1) begin
                logical_rs = i_dec_rs[(lane*OPERANDS+operand)*LOG_REG_WIDTH +: LOG_REG_WIDTH];
                source_phy = next_map[logical_rs];
                source_ready = ready_now[source_phy];
                o_ist_data[lane*INTERNAL_WIDTH + P_RS + operand*PHY_REG_WIDTH +: PHY_REG_WIDTH] = source_phy;
                o_ist_data[lane*INTERNAL_WIDTH + P_READY + operand] = source_ready;
            end

            if (creates_dest) begin
                o_fcl_retire_data[lane*RETIRE_WIDTH +: PHY_REG_WIDTH] = old_dest_phy;
                next_map[logical_rd] = dest_phy;
                ready_now[dest_phy] = 1'b0;
            end
            o_fcl_retire_data[lane*RETIRE_WIDTH + PHY_REG_WIDTH +: 1] = creates_dest;
            o_fcl_retire_data[lane*RETIRE_WIDTH + PHY_REG_WIDTH + 1 +: FLOW_WIDTH] =
                i_dec_flow[lane*FLOW_WIDTH +: FLOW_WIDTH];
            o_fcl_retire_data[lane*RETIRE_WIDTH + PHY_REG_WIDTH + 1 + FLOW_WIDTH +: PC_WIDTH] =
                i_dec_pc[lane*PC_WIDTH +: PC_WIDTH];

            if (bundle_fire && i_dec_valid[lane]) o_dec_get[lane] = 1'b1;
            if (bundle_fire && scheduled) begin
                o_fcl_retire_valid[lane] = 1'b1;
                if (creates_dest) o_prm_alloc_get[lane] = 1'b1;
                if (!control_seen && (i_dec_jump[lane] || i_dec_jump_reg[lane] || i_dec_branch[lane])) begin
                    o_fcl_control_valid = 1'b1;
                    o_fcl_control_data[0] = i_dec_jump[lane];
                    o_fcl_control_data[1] = i_dec_jump_reg[lane];
                    o_fcl_control_data[2] = i_dec_branch[lane];
                    o_fcl_control_data[3 +: PC_WIDTH] = i_dec_target_pc[lane*PC_WIDTH +: PC_WIDTH];
                    o_fcl_control_data[3+PC_WIDTH +: FLOW_WIDTH] = i_dec_flow[lane*FLOW_WIDTH +: FLOW_WIDTH];
                    o_fcl_control_data[3+PC_WIDTH+FLOW_WIDTH +: PC_WIDTH] = i_dec_pc[lane*PC_WIDTH +: PC_WIDTH];
                    control_seen = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (reg_idx = 0; reg_idx < LOG_REGS; reg_idx = reg_idx + 1) rename_map[reg_idx] <= '0;
            phy_ready <= '0;
            phy_ready[0] <= 1'b1;
        end else begin
            for (done_idx = 0; done_idx < RESULT_PORTS; done_idx = done_idx + 1) begin
                if (i_done_valid[done_idx])
                    phy_ready[i_done_phy[done_idx*PHY_REG_WIDTH +: PHY_REG_WIDTH]] <= 1'b1;
            end
            if (bundle_fire) begin
                for (reg_idx = 0; reg_idx < LOG_REGS; reg_idx = reg_idx + 1)
                    rename_map[reg_idx] <= next_map[reg_idx];
                for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
                    logical_rd = i_dec_rd[lane*LOG_REG_WIDTH +: LOG_REG_WIDTH];
                    if (lane_schedule[lane] &&
                        i_dec_writes_rd[lane] && (logical_rd != '0))
                        phy_ready[i_prm_alloc_phy[lane*PHY_REG_WIDTH +: PHY_REG_WIDTH]] <= 1'b0;
                end
            end
            phy_ready[0] <= 1'b1;
        end
    end

    initial begin
        if (LOG_REGS < 1 || OPERANDS < 1 || PHY_REGS < 2 || DECODE_WIDTH < 1)
            $error("Invalid EULSUKDO NEL parameters");
    end
endmodule
