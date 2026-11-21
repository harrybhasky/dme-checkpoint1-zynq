# Builds the whole final-project hardware for the ZedBoard in one go:
# project, Xilinx cores, block design, top level, bitstream and .xsa.
#
#   cd <repository root>
#   vivado -mode batch -source checkpoint4/vivado/build_project.tcl
#
# Optional:  -tclargs <jobs> <no_bitstream>
#   jobs          parallel jobs for synthesis/implementation (default 4)
#   no_bitstream  1 = stop after creating the project (for opening it in the GUI)
#
# Works with Vivado 2020.1 and newer (no IP versions are hard-coded). The
# course ground station's own .xci files need Vivado 2022.2, so this script
# re-creates its four Xilinx cores with the same settings instead.
#
# Output (checkpoint4/vivado/output/):
#   dme_final.xsa  hardware platform for Vitis (bitstream included)
#   dme_final.bit  bitstream
#   timing.txt, utilization.txt
# The project itself is in checkpoint4/vivado/dme_final/.
#
# Address map (must match software/main.c):
#   0x43C00000  dme_aircraft_axi4lite (aircraft DME)
#   0x43C10000  dme_gs_ctrl_axi4lite  (ground station inputs)

set jobs         [expr {[llength $argv] > 0 ? [lindex $argv 0] : 4}]
set no_bitstream [expr {[llength $argv] > 1 ? [lindex $argv 1] : 0}]

set here     [file normalize [file dirname [info script]]]
set ck4      [file normalize $here/..]
set root     [file normalize $ck4/..]
set gs_src   $ck4/ip/groundStation/project_1.srcs/sources_1/new
set proj_dir $here/dme_final
set out_dir  $here/output
set PART     xc7z020clg484-1

proc banner {msg} { puts "\n========== $msg ==========" }

# Latest version of an IP in this Vivado's catalog.
proc latest_ip {vlnv_prefix} {
    set defs [lsort -dictionary [get_ipdefs -all "${vlnv_prefix}:*"]]
    if {[llength $defs] == 0} { error "IP $vlnv_prefix not found in the catalog" }
    return [lindex $defs end]
}

# Applies CONFIG values one at a time, in order. A value this Vivado version
# rejects is reported, not fatal; check_ip_config below lists any mismatch.
proc set_config {ip pairs} {
    foreach {key value} $pairs {
        if {[catch {set_property CONFIG.$key $value [get_ips $ip]} err]} {
            puts "WARNING: $ip: CONFIG.$key = $value not applied: $err"
        }
    }
}

proc check_ip_config {ip pairs} {
    set ok 1
    foreach {key value} $pairs {
        set got [get_property CONFIG.$key [get_ips $ip]]
        if {![string equal -nocase $got $value]} {
            puts "CHECK: $ip CONFIG.$key is '$got', expected '$value'"
            set ok 0
        }
    }
    if {$ok} { puts "CHECK: $ip settings match the course IP" }
}

banner "Project"
file mkdir $out_dir
create_project dme_final $proj_dir -part $PART -force

# ZedBoard board files, if installed (Digilent or Avnet name).
set board ""
foreach pattern {*:zedboard:* em.avnet.com:zed:*} {
    set found [lsort -dictionary [get_board_parts -quiet $pattern]]
    if {[llength $found] > 0} { set board [lindex $found end]; break }
}
if {$board ne ""} {
    set_property board_part $board [current_project]
    puts "Board: $board"
} else {
    puts "WARNING: no ZedBoard board files found; using part $PART and the PS7 ZedBoard preset"
}

banner "Sources"
set rtl_files [list \
    $root/checkpoint2/rtl/dme_envelope_demodulator.sv \
    $root/checkpoint2/rtl/dme_pulse_pair_detector.sv \
    $ck4/rtl/dme_halfsine_rom.sv \
    $ck4/rtl/dme_interrogator_tx.sv \
    $ck4/rtl/dme_aircraft_axi4lite.sv \
    $ck4/rtl/dme_gs_ctrl_axi4lite.sv \
    $ck4/rtl/dme_system.sv]
# Course ground station, unmodified. mem_init.v, squitter.v and new.zip are
# leftovers that nothing instantiates.
foreach f {groundStation delayModel demodulator distanceModel mixer ppGen \
           pp_to_squit pulseBRAM pulseEfficiency pulseGen pulseMux replyGen \
           squitterGen stationIDGen} {
    lappend rtl_files $gs_src/$f.v
}
foreach f $rtl_files {
    if {![file exists $f]} { error "Missing source: $f" }
}
add_files -norecurse $rtl_files

banner "Ground station Xilinx cores"
# Settings from the course IP's .xci files (Vivado 2022.2).

# 10 MHz cosine carrier: 12-bit, fixed phase increment 0x1999999A at 100 MHz.
create_ip -name dds_compiler -vendor xilinx.com -library ip -module_name dds_compiler_0
set dds_cfg {
    PartsPresent         Phase_Generator_and_SIN_COS_LUT
    DDS_Clock_Rate       100
    Parameter_Entry      Hardware_Parameters
    Phase_Width          32
    Output_Width         12
    Phase_Increment      Fixed
    Phase_offset         None
    Output_Selection     Cosine
    Noise_Shaping        None
    Has_Phase_Out        false
    PINC1                00011001100110011001100110011010
    Latency_Configuration Auto
}
set_config dds_compiler_0 $dds_cfg

# Squitter period 1e8 / pulse rate: 28-bit / 12-bit unsigned, remainder.
create_ip -name div_gen -vendor xilinx.com -library ip -module_name div_gen_0
set div0_cfg {
    algorithm_type              Radix2
    dividend_and_quotient_width 28
    divisor_width               12
    remainder_type              Remainder
    fractional_width            12
    operand_sign                Unsigned
    clocks_per_division         1
    divide_by_zero_detect       false
    FlowControl                 NonBlocking
    OptimizeGoal                Performance
    latency_configuration       Automatic
}
set_config div_gen_0 $div0_cfg

# Seconds per km 1000 / speed: 12-bit / 8-bit unsigned, remainder.
create_ip -name div_gen -vendor xilinx.com -library ip -module_name div_gen_1
set div1_cfg {
    algorithm_type              Radix2
    dividend_and_quotient_width 12
    divisor_width               8
    remainder_type              Remainder
    fractional_width            8
    operand_sign                Unsigned
    clocks_per_division         1
    divide_by_zero_detect       false
    FlowControl                 NonBlocking
    OptimizeGoal                Performance
    latency_configuration       Automatic
}
set_config div_gen_1 $div1_cfg

# Delay line: 1 bit wide, 131072 deep, block RAM, synchronous reset.
create_ip -name fifo_generator -vendor xilinx.com -library ip -module_name fifo_generator_0
set fifo_cfg {
    INTERFACE_TYPE       Native
    Fifo_Implementation  Common_Clock_Block_RAM
    Performance_Options  Standard_FIFO
    Input_Data_Width     1
    Input_Depth          131072
    Output_Data_Width    1
    Output_Depth         131072
    Reset_Pin            true
    Reset_Type           Synchronous_Reset
    Use_Dout_Reset       true
}
set_config fifo_generator_0 $fifo_cfg

check_ip_config dds_compiler_0 $dds_cfg
check_ip_config div_gen_0 $div0_cfg
check_ip_config div_gen_1 $div1_cfg
check_ip_config fifo_generator_0 $fifo_cfg
# The latencies the ground station's timing was built with.
foreach {ip key value} {dds_compiler_0 Latency 7 div_gen_0 latency 30 div_gen_1 latency 14} {
    set got [get_property CONFIG.$key [get_ips $ip]]
    if {$got != $value} { puts "CHECK: $ip latency is $got, the course IP used $value" }
}
generate_target all [get_ips]

banner "Block design: Zynq PS, AXI interconnect, two AXI4-Lite ports"
create_bd_design design_1

set ps [create_bd_cell -type ip -vlnv [latest_ip xilinx.com:ip:processing_system7] processing_system7_0]
if {$board ne ""} {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
} else {
    set_property CONFIG.preset {ZedBoard} $ps
    make_bd_intf_pins_external [get_bd_intf_pins $ps/DDR] [get_bd_intf_pins $ps/FIXED_IO]
    set_property name DDR [get_bd_intf_ports DDR_0]
    set_property name FIXED_IO [get_bd_intf_ports FIXED_IO_0]
}
set_property -dict [list \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} \
    ] $ps

set ic [create_bd_cell -type ip -vlnv [latest_ip xilinx.com:ip:axi_interconnect] axi_interconnect_0]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $ic
set rst [create_bd_cell -type ip -vlnv [latest_ip xilinx.com:ip:proc_sys_reset] rst_ps7_0_100M]

foreach name {M_AXI_AC M_AXI_GSC} {
    create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 $name
    set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {32} \
                             CONFIG.DATA_WIDTH {32}] [get_bd_intf_ports $name]
}
create_bd_port -dir O -type clk FCLK_CLK0
set_property CONFIG.ASSOCIATED_BUSIF {M_AXI_AC:M_AXI_GSC} [get_bd_ports FCLK_CLK0]
create_bd_port -dir O -type rst peripheral_aresetn

connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins $ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic/M00_AXI] [get_bd_intf_ports M_AXI_AC]
connect_bd_intf_net [get_bd_intf_pins $ic/M01_AXI] [get_bd_intf_ports M_AXI_GSC]

connect_bd_net [get_bd_pins $ps/FCLK_CLK0] \
    [get_bd_pins $ps/M_AXI_GP0_ACLK] \
    [get_bd_pins $ic/ACLK] [get_bd_pins $ic/S00_ACLK] \
    [get_bd_pins $ic/M00_ACLK] [get_bd_pins $ic/M01_ACLK] \
    [get_bd_pins $rst/slowest_sync_clk] [get_bd_ports FCLK_CLK0]
connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $rst/interconnect_aresetn] [get_bd_pins $ic/ARESETN]
connect_bd_net [get_bd_pins $rst/peripheral_aresetn] \
    [get_bd_pins $ic/S00_ARESETN] [get_bd_pins $ic/M00_ARESETN] \
    [get_bd_pins $ic/M01_ARESETN] [get_bd_ports peripheral_aresetn]

# External ports take the PS clock's exact frequency and the reset's polarity,
# so validation finds no property mismatch.
set fclk_hz [get_property CONFIG.FREQ_HZ [get_bd_pins $ps/FCLK_CLK0]]
puts "FCLK_CLK0: $fclk_hz Hz"
set_property CONFIG.FREQ_HZ $fclk_hz [get_bd_ports FCLK_CLK0]
foreach name {M_AXI_AC M_AXI_GSC} {
    set_property CONFIG.FREQ_HZ $fclk_hz [get_bd_intf_ports $name]
}
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports peripheral_aresetn]

assign_bd_address
foreach {name offset} {M_AXI_AC 0x43C00000 M_AXI_GSC 0x43C10000} {
    set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $ps/Data] -filter "NAME =~ *${name}*"]
    if {[llength $seg] != 1} { error "Address segment for $name not found: '$seg'" }
    set_property range 64K $seg
    set_property offset $offset $seg
    puts "Address: $name at $offset (64K)"
}

validate_bd_design
save_bd_design
set bd_file [get_files design_1.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper

banner "Top level"
# system_top.v: the block design wrapper plus dme_system. The DDR and
# FIXED_IO ports are copied from the generated wrapper, so their names and
# widths always match this Vivado version.
set fh [open $wrapper r]
set wrapper_text [read $fh]
close $fh
set ports {}
foreach line [split $wrapper_text "\n"] {
    if {[regexp {^\s*(input|output|inout)\s*(\[[0-9]+:[0-9]+\])?\s*(\w+)\s*;} $line -> dir width name]} {
        lappend ports [list $dir $width $name]
    }
}
if {[llength $ports] == 0} { error "Could not read the ports of $wrapper" }

set axi_signals {awaddr awvalid awready wdata wstrb wvalid wready bresp bvalid bready
                 araddr arvalid arready rdata rresp rvalid rready}
set top_ports {}
set top_decls {}
set wires {}
set bd_conns {}
set sys_conns {}
foreach p $ports {
    lassign $p dir width name
    if {[regexp {^(DDR|FIXED_IO)_} $name]} {
        lappend top_ports $name
        lappend top_decls "    $dir $width $name;"
        lappend bd_conns "        .$name($name)"
    } elseif {[regexp {^M_AXI_(AC|GSC)_(\w+)$} $name -> which sig]} {
        lappend wires "    wire $width $name;"
        lappend bd_conns "        .$name($name)"
        if {[lsearch -exact $axi_signals $sig] >= 0} {
            lappend sys_conns "        .[string tolower $which]_$sig\($name\)"
        }
    } elseif {$name eq "FCLK_CLK0" || $name eq "peripheral_aresetn"} {
        lappend wires "    wire $name;"
        lappend bd_conns "        .$name\($name\)"
    } else {
        error "Unexpected block design port $name"
    }
}
lappend sys_conns "        .clk(FCLK_CLK0)" "        .rstn(peripheral_aresetn)"

set top_file $out_dir/system_top.v
set fh [open $top_file w]
puts $fh "// Generated by checkpoint4/vivado/build_project.tcl. Do not edit."
puts $fh "module system_top ([join $top_ports {, }]);"
puts $fh [join $top_decls "\n"]
puts $fh [join $wires "\n"]
puts $fh "    design_1_wrapper bd (\n[join $bd_conns ",\n"]\n    );"
puts $fh "    dme_system dme (\n[join $sys_conns ",\n"]\n    );"
puts $fh "endmodule"
close $fh
add_files -norecurse $top_file
set_property top system_top [current_fileset]
update_compile_order -fileset sources_1
puts "Top level: $top_file"

if {$no_bitstream} {
    puts "\nProject created: $proj_dir/dme_final.xpr (no bitstream requested)"
    return
}

banner "Synthesis"
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed: see $proj_dir/dme_final.runs/synth_1/runme.log"
}

banner "Implementation and bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation failed: see $proj_dir/dme_final.runs/impl_1/runme.log"
}

open_run impl_1
report_timing_summary -file $out_dir/timing.txt
report_utilization -file $out_dir/utilization.txt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set bit [glob -nocomplain $proj_dir/dme_final.runs/impl_1/*.bit]
file copy -force [lindex $bit 0] $out_dir/dme_final.bit
write_hw_platform -fixed -include_bit -force -file $out_dir/dme_final.xsa

banner "Done"
puts "Bitstream: $out_dir/dme_final.bit"
puts "Platform:  $out_dir/dme_final.xsa"
puts "Worst setup slack: $wns ns [expr {$wns >= 0 ? {(timing met)} : {(TIMING NOT MET: see timing.txt)}}]"
