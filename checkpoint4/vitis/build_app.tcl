# Builds the bare-metal application with Vitis (classic) / XSCT.
#
#   cd <repository root>
#   xsct checkpoint4/vitis/build_app.tcl
#
# Needs checkpoint4/vivado/output/dme_final.xsa (from build_project.tcl).
# Creates checkpoint4/vitis/workspace with a standalone platform for
# ps7_cortexa9_0 and the application dme_app, built from
# checkpoint4/software (main.c, dme_track.c and the two drivers).
# Output: checkpoint4/vitis/workspace/dme_app/Debug/dme_app.elf

set here [file normalize [file dirname [info script]]]
set ck4  [file normalize $here/..]
set xsa  $ck4/vivado/output/dme_final.xsa
set sw   $ck4/software
set ws   $here/workspace

if {![file exists $xsa]} { error "Missing $xsa: run checkpoint4/vivado/build_project.tcl first" }

# The workspace is generated: start clean so a rebuild picks up a new .xsa.
file delete -force $ws
file mkdir $ws
setws $ws

# The template name differs between Vitis versions.
set created 0
foreach template {{Empty Application} {Empty Application(C)}} {
    if {![catch {app create -name dme_app -hw $xsa -proc ps7_cortexa9_0 \
                    -os standalone -lang C -template $template} err]} {
        set created 1
        break
    }
    puts "app create with template '$template' failed: $err"
}
if {!$created} { error "Could not create the application" }

foreach f {main.c dme_track.c dme_track.h dme_aircraft_driver.c dme_aircraft_driver.h
           dme_gs_ctrl_driver.c dme_gs_ctrl_driver.h} {
    importsources -name dme_app -path $sw/$f
}

app build -name dme_app
set elf [glob -nocomplain $ws/dme_app/Debug/*.elf $ws/dme_app/Release/*.elf]
if {[llength $elf] == 0} { error "Build produced no .elf: see the messages above" }
puts "\nApplication: [lindex $elf 0]"
