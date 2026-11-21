# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CARRIER_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CLK_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DEFAULT_PAIR_RATE_HZ" -parent ${Page_0}
  ipgui::add_param $IPINST -name "INTER_PULSE_DELAY_US" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PULSE_WIDTH_US" -parent ${Page_0}


}

proc update_PARAM_VALUE.CARRIER_HZ { PARAM_VALUE.CARRIER_HZ } {
	# Procedure called to update CARRIER_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CARRIER_HZ { PARAM_VALUE.CARRIER_HZ } {
	# Procedure called to validate CARRIER_HZ
	return true
}

proc update_PARAM_VALUE.CLK_HZ { PARAM_VALUE.CLK_HZ } {
	# Procedure called to update CLK_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CLK_HZ { PARAM_VALUE.CLK_HZ } {
	# Procedure called to validate CLK_HZ
	return true
}

proc update_PARAM_VALUE.DEFAULT_PAIR_RATE_HZ { PARAM_VALUE.DEFAULT_PAIR_RATE_HZ } {
	# Procedure called to update DEFAULT_PAIR_RATE_HZ when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DEFAULT_PAIR_RATE_HZ { PARAM_VALUE.DEFAULT_PAIR_RATE_HZ } {
	# Procedure called to validate DEFAULT_PAIR_RATE_HZ
	return true
}

proc update_PARAM_VALUE.INTER_PULSE_DELAY_US { PARAM_VALUE.INTER_PULSE_DELAY_US } {
	# Procedure called to update INTER_PULSE_DELAY_US when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INTER_PULSE_DELAY_US { PARAM_VALUE.INTER_PULSE_DELAY_US } {
	# Procedure called to validate INTER_PULSE_DELAY_US
	return true
}

proc update_PARAM_VALUE.PULSE_WIDTH_US { PARAM_VALUE.PULSE_WIDTH_US } {
	# Procedure called to update PULSE_WIDTH_US when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PULSE_WIDTH_US { PARAM_VALUE.PULSE_WIDTH_US } {
	# Procedure called to validate PULSE_WIDTH_US
	return true
}


proc update_MODELPARAM_VALUE.CLK_HZ { MODELPARAM_VALUE.CLK_HZ PARAM_VALUE.CLK_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CLK_HZ}] ${MODELPARAM_VALUE.CLK_HZ}
}

proc update_MODELPARAM_VALUE.CARRIER_HZ { MODELPARAM_VALUE.CARRIER_HZ PARAM_VALUE.CARRIER_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CARRIER_HZ}] ${MODELPARAM_VALUE.CARRIER_HZ}
}

proc update_MODELPARAM_VALUE.PULSE_WIDTH_US { MODELPARAM_VALUE.PULSE_WIDTH_US PARAM_VALUE.PULSE_WIDTH_US } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PULSE_WIDTH_US}] ${MODELPARAM_VALUE.PULSE_WIDTH_US}
}

proc update_MODELPARAM_VALUE.INTER_PULSE_DELAY_US { MODELPARAM_VALUE.INTER_PULSE_DELAY_US PARAM_VALUE.INTER_PULSE_DELAY_US } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INTER_PULSE_DELAY_US}] ${MODELPARAM_VALUE.INTER_PULSE_DELAY_US}
}

proc update_MODELPARAM_VALUE.DEFAULT_PAIR_RATE_HZ { MODELPARAM_VALUE.DEFAULT_PAIR_RATE_HZ PARAM_VALUE.DEFAULT_PAIR_RATE_HZ } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DEFAULT_PAIR_RATE_HZ}] ${MODELPARAM_VALUE.DEFAULT_PAIR_RATE_HZ}
}

