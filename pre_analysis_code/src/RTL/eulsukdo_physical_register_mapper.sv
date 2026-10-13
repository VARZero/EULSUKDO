`timescale 1ns/1ps

module eulsukdo_physical_register_mapper #(
    parameter int unsigned DECODE_WIDTH  = 2,
    parameter int unsigned OPERANDS      = 2,
    parameter int unsigned IST_ENTRIES   = 128,
    parameter int unsigned PHY_REGS      = 64,
    parameter int unsigned DEPTH_PER_REG = 4,
    parameter int unsigned WAKE_PORTS    = 5,
    parameter int unsigned FREE_PORTS    = 4,
    parameter int unsigned RESULT_PORTS  = 5,
    parameter int unsigned IST_WIDTH     = (IST_ENTRIES <= 1) ? 1 : $clog2(IST_ENTRIES),
    parameter int unsigned PHY_REG_WIDTH = (PHY_REGS <= 1) ? 1 : $clog2(PHY_REGS),
    parameter int unsigned DEP_WIDTH     = PHY_REG_WIDTH + IST_WIDTH,
    parameter int unsigned PTR_WIDTH     = (DEPTH_PER_REG <= 1) ? 1 : $clog2(DEPTH_PER_REG),
    parameter int unsigned COUNT_WIDTH   = $clog2(DEPTH_PER_REG + 1)
) (
    input  logic                              clk,
    input  logic                              reset_n,

    input  logic [DECODE_WIDTH-1:0]           i_alloc_req,
    output logic [DECODE_WIDTH-1:0]           o_alloc_valid,
    output logic [DECODE_WIDTH*PHY_REG_WIDTH-1:0] o_alloc_phy,
    input  logic [DECODE_WIDTH-1:0]           i_alloc_get,

    input  logic [DECODE_WIDTH*OPERANDS-1:0]  i_dep_valid,
    input  logic [DECODE_WIDTH*OPERANDS*DEP_WIDTH-1:0] i_dep_data,
    input  logic                              i_dep_commit,
    output logic                              o_dep_ready,

    input  logic [RESULT_PORTS-1:0]           i_done_valid,
    input  logic [RESULT_PORTS*PHY_REG_WIDTH-1:0] i_done_phy,

    output logic [WAKE_PORTS-1:0]             o_wake_valid,
    output logic [WAKE_PORTS*DEP_WIDTH-1:0]   o_wake_data,
    input  logic [WAKE_PORTS-1:0]             i_wake_get,

    input  logic [FREE_PORTS-1:0]             i_free_valid,
    input  logic [FREE_PORTS*PHY_REG_WIDTH-1:0] i_free_phy
);
    localparam int unsigned DEP_CHANNELS = DECODE_WIDTH * OPERANDS;

    logic [PHY_REGS-1:0] allocated;
    logic [PHY_REGS-1:0] alloc_chosen;
    logic [PHY_REGS-1:0] completion_pending;
    logic [IST_WIDTH-1:0] dep_mem [0:PHY_REGS-1][0:DEPTH_PER_REG-1];
    logic [PTR_WIDTH-1:0] read_ptr [0:PHY_REGS-1];
    logic [PTR_WIDTH-1:0] write_ptr [0:PHY_REGS-1];
    logic [COUNT_WIDTH-1:0] dep_count [0:PHY_REGS-1];
    logic [PHY_REG_WIDTH-1:0] wake_phy_sel [0:WAKE_PORTS-1];
    integer selected_per_phy [0:PHY_REGS-1];
    integer incoming_per_phy [0:PHY_REGS-1];
    integer lane;
    integer phys;
    integer channel;
    integer port;
    integer slot;
    integer found;
    integer enqueue_count;
    integer dequeue_count;
    integer mem_index;
    logic [PHY_REG_WIDTH-1:0] dep_phy;
    logic [IST_WIDTH-1:0] dep_ist;
    logic [PHY_REG_WIDTH-1:0] free_phy;
    logic [PHY_REG_WIDTH-1:0] done_phy;

    always_comb begin
        mem_index = 0;
        alloc_chosen = allocated;
        alloc_chosen[0] = 1'b1;
        o_alloc_valid = '0;
        o_alloc_phy = '0;
        for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
            found = 0;
            if (i_alloc_req[lane]) begin
                for (phys = 1; phys < PHY_REGS; phys = phys + 1) begin
                    if (!alloc_chosen[phys] && (found == 0)) begin
                        o_alloc_valid[lane] = 1'b1;
                        o_alloc_phy[lane*PHY_REG_WIDTH +: PHY_REG_WIDTH] = PHY_REG_WIDTH'(phys);
                        alloc_chosen[phys] = 1'b1;
                        found = 1;
                    end
                end
            end
        end

        for (phys = 0; phys < PHY_REGS; phys = phys + 1) incoming_per_phy[phys] = 0;
        for (channel = 0; channel < DEP_CHANNELS; channel = channel + 1) begin
            dep_phy = i_dep_data[channel*DEP_WIDTH +: PHY_REG_WIDTH];
            if (i_dep_valid[channel]) incoming_per_phy[dep_phy] = incoming_per_phy[dep_phy] + 1;
        end
        o_dep_ready = 1'b1;
        for (phys = 0; phys < PHY_REGS; phys = phys + 1) begin
            if ((dep_count[phys] + incoming_per_phy[phys]) > DEPTH_PER_REG) o_dep_ready = 1'b0;
        end

        for (phys = 0; phys < PHY_REGS; phys = phys + 1) selected_per_phy[phys] = 0;
        o_wake_valid = '0;
        o_wake_data = '0;
        for (port = 0; port < WAKE_PORTS; port = port + 1) begin
            found = 0;
            wake_phy_sel[port] = '0;
            for (phys = 1; phys < PHY_REGS; phys = phys + 1) begin
                if (completion_pending[phys] &&
                    (selected_per_phy[phys] < dep_count[phys]) && (found == 0)) begin
                    wake_phy_sel[port] = PHY_REG_WIDTH'(phys);
                    mem_index = (read_ptr[phys] + selected_per_phy[phys]) % DEPTH_PER_REG;
                    o_wake_valid[port] = 1'b1;
                    o_wake_data[port*DEP_WIDTH +: PHY_REG_WIDTH] = PHY_REG_WIDTH'(phys);
                    o_wake_data[port*DEP_WIDTH + PHY_REG_WIDTH +: IST_WIDTH] = dep_mem[phys][mem_index];
                    selected_per_phy[phys] = selected_per_phy[phys] + 1;
                    found = 1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            allocated <= '0;
            allocated[0] <= 1'b1;
            completion_pending <= '0;
            for (phys = 0; phys < PHY_REGS; phys = phys + 1) begin
                read_ptr[phys] <= '0;
                write_ptr[phys] <= '0;
                dep_count[phys] <= '0;
                for (slot = 0; slot < DEPTH_PER_REG; slot = slot + 1)
                    dep_mem[phys][slot] <= '0;
            end
        end else begin
            for (lane = 0; lane < DECODE_WIDTH; lane = lane + 1) begin
                if (i_alloc_req[lane] && o_alloc_valid[lane] && i_alloc_get[lane])
                    allocated[o_alloc_phy[lane*PHY_REG_WIDTH +: PHY_REG_WIDTH]] <= 1'b1;
            end
            for (port = 0; port < FREE_PORTS; port = port + 1) begin
                free_phy = i_free_phy[port*PHY_REG_WIDTH +: PHY_REG_WIDTH];
                if (i_free_valid[port] && (free_phy != '0)) allocated[free_phy] <= 1'b0;
            end
            allocated[0] <= 1'b1;

            for (port = 0; port < RESULT_PORTS; port = port + 1) begin
                done_phy = i_done_phy[port*PHY_REG_WIDTH +: PHY_REG_WIDTH];
                if (i_done_valid[port] && (done_phy != '0)) completion_pending[done_phy] <= 1'b1;
            end

            for (phys = 1; phys < PHY_REGS; phys = phys + 1) begin
                enqueue_count = 0;
                if (i_dep_commit && o_dep_ready) begin
                    for (channel = 0; channel < DEP_CHANNELS; channel = channel + 1) begin
                        dep_phy = i_dep_data[channel*DEP_WIDTH +: PHY_REG_WIDTH];
                        dep_ist = i_dep_data[channel*DEP_WIDTH + PHY_REG_WIDTH +: IST_WIDTH];
                        if (i_dep_valid[channel] && (dep_phy == PHY_REG_WIDTH'(phys))) begin
                            mem_index = (write_ptr[phys] + enqueue_count) % DEPTH_PER_REG;
                            dep_mem[phys][mem_index] <= dep_ist;
                            enqueue_count = enqueue_count + 1;
                        end
                    end
                end

                dequeue_count = 0;
                for (port = 0; port < WAKE_PORTS; port = port + 1) begin
                    if (o_wake_valid[port] && i_wake_get[port] &&
                        (wake_phy_sel[port] == PHY_REG_WIDTH'(phys)))
                        dequeue_count = dequeue_count + 1;
                end

                if (enqueue_count != 0)
                    write_ptr[phys] <= PTR_WIDTH'((write_ptr[phys] + enqueue_count) % DEPTH_PER_REG);
                if (dequeue_count != 0)
                    read_ptr[phys] <= PTR_WIDTH'((read_ptr[phys] + dequeue_count) % DEPTH_PER_REG);
                if ((enqueue_count != 0) || (dequeue_count != 0))
                    dep_count[phys] <= COUNT_WIDTH'(dep_count[phys] + enqueue_count - dequeue_count);
                if (completion_pending[phys] &&
                    ((dep_count[phys] + enqueue_count - dequeue_count) == 0))
                    completion_pending[phys] <= 1'b0;
            end
        end
    end

    initial begin
        if (PHY_REGS < 2 || DEPTH_PER_REG < 1 || WAKE_PORTS < 1)
            $error("Invalid EULSUKDO PRM parameters");
    end
endmodule
