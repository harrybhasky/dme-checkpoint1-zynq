# Programs the ZedBoard over JTAG and runs the application.
#
#   cd <repository root>
#   xsct checkpoint4/vitis/run_on_board.tcl
#
# Before running: ZedBoard boot jumpers JP7-JP11 all to GND (JTAG boot),
# power on, USB cable on PROG (J17) for JTAG and on UART (J14) for the
# console. Open a serial terminal at 115200 8N1 on the UART's COM port
# first, to see the start-up messages.
#
# Same steps as Vitis "Run As > Launch Hardware": reset, bitstream,
# ps7_init, download the .elf, run.

set here [file normalize [file dirname [info script]]]
set ck4  [file normalize $here/..]
set ws   $here/workspace
set bit  $ck4/vivado/output/dme_final.bit
set xsa  $ck4/vivado/output/dme_final.xsa
set elf  [lindex [glob -nocomplain $ws/dme_app/Debug/*.elf $ws/dme_app/Release/*.elf] 0]

proc find_file {dir name} {
    foreach f [glob -nocomplain -directory $dir -types f $name] { return $f }
    foreach d [glob -nocomplain -directory $dir -types d *] {
        set f [find_file $d $name]
        if {$f ne ""} { return $f }
    }
    return ""
}
set ps7_init [find_file $ws ps7_init.tcl]

foreach {what f} [list bitstream $bit platform $xsa application $elf ps7_init.tcl $ps7_init] {
    if {$f eq "" || ![file exists $f]} { error "Missing $what ($f): build the hardware and the application first" }
}

connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 1000
targets -set -nocase -filter {name =~ "xc7z*"}
fpga -file $bit
targets -set -nocase -filter {name =~ "APU*"}
loadhw -hw $xsa -mem-ranges [list {0x40000000 0xbfffffff}] -regs
configparams force-mem-access 1
source $ps7_init
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "*A9*#0"}
dow $elf
configparams force-mem-access 0
con
puts "Running [file tail $elf]: see the UART terminal (115200 8N1)"
