if {$argc != 3} {error "Expected OUTPUT_DIR MHZ THREADS"}
set output [file normalize [lindex $argv 0]]
set mhz [lindex $argv 1]
set threads [lindex $argv 2]
cd $output
set part xc7z020clg400-1
set clock_period [expr {1000.0/$mhz}]
set_param general.maxThreads $threads
set status [open status.txt w]
proc stage {name} {
    global status
    puts $status "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $name"
    flush $status
    puts "STAGE $name"
}
proc reports {prefix} {
    global mhz clock_site
    report_utilization -file ${prefix}_utilization.rpt
    report_utilization -hierarchical -file ${prefix}_hierarchy.rpt
    report_timing_summary -delay_type min_max -max_paths 10 -report_unconstrained -file ${prefix}_timing_summary.rpt
    report_timing -from [all_registers] -to [all_registers] -delay_type max -max_paths 20 -path_type full_clock_expanded -file ${prefix}_reg_to_reg.rpt
    check_timing -verbose -file ${prefix}_check_timing.rpt
    report_drc -file ${prefix}_drc.rpt
    report_drc -checks [get_drc_checks LUTLP-1] -file ${prefix}_lut_loops.rpt
    set f [open ${prefix}_summary.txt w]
    puts $f "Vivado [version -short]; 2d5i LSQ=1 depth=32 path=2; $mhz MHz; $prefix"
    puts $f "OOC internal scheduler timing only; clock source $clock_site; external IO/board excluded"
    puts $f "Latches: [llength [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]]"
    puts $f "Black boxes: [llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]]"
    foreach p [get_timing_paths -from [all_registers] -to [all_registers] -delay_type max -max_paths 1] {
        puts $f "Setup slack: [get_property SLACK $p] ns"
        puts $f "Data path delay: [get_property DATAPATH_DELAY $p] ns"
        puts $f "Logic levels: [get_property LOGIC_LEVELS $p]"
        puts $f "Startpoint: [get_property STARTPOINT_PIN $p]"
        puts $f "Endpoint: [get_property ENDPOINT_PIN $p]"
    }
    foreach p [get_timing_paths -from [all_registers] -to [all_registers] -delay_type min -max_paths 1] {
        puts $f "Hold slack: [get_property SLACK $p] ns"
    }
    close $f
    set lsq_regs [get_cells -hier -quiet -filter {NAME =~ *U_LSQ* && IS_SEQUENTIAL == 1}]
    if {![llength $lsq_regs]} {error "LSQ registers absent from enabled implementation"}
    report_timing -from $lsq_regs -to [all_registers] -max_paths 5 -file ${prefix}_lsq_from.rpt
    report_timing -from [all_registers] -to $lsq_regs -max_paths 5 -file ${prefix}_lsq_to.rpt
}
proc measure {frequency} {
    create_clock -name clk -period [expr {1000.0/$frequency}] [get_ports clk]
    if {[llength [get_clocks]] != 1} {error "Expected one clock"}
    return [get_property SLACK [get_timing_paths -from [all_registers] -to [all_registers] -delay_type max -max_paths 1]]
}
stage START
create_project -in_memory -part $part
read_verilog -sv [glob [file join $output source *.sv]]
set f [open clock.xdc w]
puts $f "create_clock -name clk -period $clock_period \[get_ports clk\]"
close $f
read_xdc clock.xdc
stage SYNTHESIS
synth_design -top eulsukdo_scheduler -part $part -mode out_of_context -generic {ENABLE_LSQ=1 STRUCT_LSQ_ENTRIES=32 STRUCT_LSQ_EX_PATH=2}
set sites [lsort -dictionary [get_sites -filter {SITE_TYPE == BUFGCTRL}]]
if {![llength $sites]} {error "No clock site"}
set clock_site [lindex $sites [expr {[llength $sites]/2}]]
set_property HD.CLK_SRC $clock_site [get_ports clk]
write_checkpoint -force scheduler_synth.dcp
stage SYNTH_REPORTS
reports synth
stage OPTIMIZATION
opt_design
write_checkpoint -force scheduler_opt.dcp
stage PLACEMENT
place_design
write_checkpoint -force scheduler_placed.dcp
stage PLACED_REPORTS
reports placed
stage ROUTING
route_design
write_checkpoint -force scheduler_routed.dcp
stage ROUTED_REPORTS
reports routed
report_route_status -file routed_route_status.rpt
report_clocks -file routed_clocks.rpt

# Measure the timing boundary of THIS routing, without resynthesis or rerouting.
# Search in 0.1 MHz increments, then save full setup/hold/pulse-width reports.
stage FIXED_ROUTE_CLOCK_SWEEP
file mkdir sweep
set low 200
set high 1500
if {[measure [expr {$low/10.0}]] < 0 || [measure [expr {$high/10.0}]] >= 0} {
    error "Timing boundary outside 20..150 MHz search interval"
}
while {$high-$low > 1} {
    set mid [expr {($low+$high)/2}]
    if {[measure [expr {$mid/10.0}]] >= 0} {set low $mid} else {set high $mid}
}
set best [expr {$low/10.0}]
set fail [expr {$high/10.0}]
set margin [expr {floor($best*0.95/5.0)*5.0}]
set csv [open sweep/results.csv w]
puts $csv "mhz,period_ns,setup_slack_ns,hold_slack_ns"
foreach frequency [lsort -real -unique [list $mhz $best $fail $margin 70 75]] {
    set setup [measure $frequency]
    set hold [get_property SLACK [get_timing_paths -from [all_registers] -to [all_registers] -delay_type min -max_paths 1]]
    set tag [string map {. p} $frequency]
    report_timing_summary -delay_type min_max -report_unconstrained -max_paths 3 -file sweep/${tag}mhz_timing_summary.rpt
    report_clocks -file sweep/${tag}mhz_clocks.rpt
    puts $csv "$frequency,[get_property PERIOD [get_clocks clk]],$setup,$hold"
    flush $csv
    if {$frequency == $margin || $frequency == $best} {
        write_checkpoint -force sweep/scheduler_routed_${tag}mhz.dcp
        set f [open sweep/clock_${tag}mhz.xdc w]
        puts $f "create_clock -name clk -period [expr {1000.0/$frequency}] \[get_ports clk\]"
        close $f
    }
}
close $csv
stage COMPLETE
close $status
exit
