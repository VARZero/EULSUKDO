`timescale 1ns/1ps
module tb_rs_banked_queue #(
    parameter int WRITES=8, READS=3, ENTRIES=128
);
    localparam int WIDTH=32, DEPTH=(ENTRIES+WRITES-1)/WRITES;
    logic clk=0, reset_n=0;
    always #5 clk=~clk;
    logic [WRITES-1:0] push='0;
    wire [WRITES-1:0] ready;
    logic [WRITES*WIDTH-1:0] data='0;
    logic [READS-1:0] pop='0;
    wire [READS-1:0] valid;
    wire [READS*WIDTH-1:0] result;
    bit live[100000];
    int next_id=1, received=0, sent=0, full_run=0, longest_run=0;
    logic [READS-1:0] held='0;
    logic [WIDTH-1:0] held_data[READS];
    rs_banked_queue #(.DATA_WIDTH(WIDTH),.READ_CHANNEL(READS),
        .WRITE_CHANNEL(WRITES),.MIN_FIFO_ENTRY(ENTRIES)) dut (
        .clk(clk),.reset_n(reset_n),.i_push(push),.o_push_ready(ready),
        .i_push_data(data),.i_pop(pop),.o_pop_valid(valid),.o_pop_data(result)
    );
    always @(posedge clk) begin
        if (!reset_n) begin
            for (int n=0;n<100000;n++) live[n]=0;
            held='0; sent=0; received=0; full_run=0; longest_run=0;
        end else begin
            if (&(valid & pop)) full_run++; else full_run=0;
            if (full_run>longest_run) longest_run=full_run;
            for (int r=0;r<READS;r++) begin
                automatic int id=int'(result[r*WIDTH +: WIDTH]);
                if (held[r] && (!valid[r] || result[r*WIDTH +: WIDTH]!==held_data[r]))
                    $fatal(1,"Output changed while stalled");
                if (valid[r]) begin
                    if (id<=0 || id>=100000 || !live[id]) $fatal(1,"Unexpected output %0d",id);
                    for (int j=0;j<r;j++)
                        if(valid[j] && result[j*WIDTH +: WIDTH]==32'(id)) $fatal(1,"Duplicate offer");
                    if(pop[r]) begin live[id]=0; received++; end
                end
                held[r]=valid[r] && !pop[r]; held_data[r]=result[r*WIDTH +: WIDTH];
            end
            for(int w=0;w<WRITES;w++) if(push[w] && ready[w]) begin
                automatic int id=int'(data[w*WIDTH +: WIDTH]);
                if(live[id]) $fatal(1,"Repeated input");
                live[id]=1; sent++;
            end
        end
    end
    task automatic step;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic drive(input int hot_bank);
        for(int w=0;w<WRITES;w++) begin
            push[w]=ready[w] && (hot_bank<0 || hot_bank==w);
            data[w*WIDTH +: WIDTH]=32'(next_id++);
        end
    endtask
    task automatic drain;
        push='0;pop='1;
        for(int t=0;t<ENTRIES*5+100;t++) begin
            step();
            if(sent==received) begin
                repeat(5) step();
                if(|valid) $fatal(1,"Residual output");
                return;
            end
        end
        $fatal(1,"Lost/starved entries sent=%0d received=%0d",sent,received);
    endtask
    initial begin
        repeat(3) step();reset_n=1;
        // Fill every bank, then drain without bubbles when enough heads exist.
        repeat(DEPTH+READS+5) begin drive(-1);step();end
        drain();
        if(DEPTH>=8 && WRITES>=READS && longest_run<8)
            $fatal(1,"Missing sustained full-width issue: %0d",longest_run);
        // Simultaneous reads/writes, sparse output Get, all banks then one hot bank.
        for(int t=0;t<600;t++) begin
            for(int r=0;r<READS;r++) pop[r]=((t+r)%5)!=0;
            drive(t<300 ? -1 : t%WRITES);step();
        end
        drain();
        $display("PASS RS queue W=%0d R=%0d E=%0d sent=%0d received=%0d full_run=%0d",
            WRITES,READS,ENTRIES,sent,received,longest_run);
        $finish;
    end
    initial begin #1000000;$fatal(1,"Watchdog");end
endmodule
