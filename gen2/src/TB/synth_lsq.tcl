# Standalone LSQ synthesis smoke check. No placement, routing or clock claim.
# vivado -mode batch -source gen2/src/TB/synth_lsq.tcl -tclargs OUTPUT_DIR
if {$argc != 1} {error "Expected OUTPUT_DIR"}
set rtl [file normalize [file join [file dirname [info script]] ../RTL/load_store_queue.sv]]
set output [file normalize [lindex $argv 0]]
file mkdir $output
cd $output
set_param general.maxThreads 4
foreach {name generics} {
    default32 {DEPTH=32 ORDER_CHANNELS=2 READY_CHANNELS=1}
    multi7 {DEPTH=7 ORDER_CHANNELS=3 READY_CHANNELS=3}
} {
    create_project -in_memory -part xc7z020clg400-1
    read_verilog -sv $rtl
    synth_design -top load_store_queue -part xc7z020clg400-1 -mode out_of_context -generic $generics
    if {[llength [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]]} {error "LSQ inferred a latch"}
    if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]]} {error "LSQ has a black box"}
    report_utilization -file [file join $output ${name}_utilization.rpt]
    write_checkpoint -force [file join $output ${name}_synth.dcp]
    close_project
}
puts "PASS LSQ synthesis: default32 and multi7"
exit
