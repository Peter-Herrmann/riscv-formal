#!/bin/bash

assume_picorv32_asserts=false
solver="bmc3_aig"
insn="addi"
n=20

while getopts as:i:n: opt; do
	case "$opt" in
		a) assume_picorv32_asserts=true;;
		s) solver="$OPTARG";;
		i) insn="$OPTARG";;
		n) n="$OPTARG";;
		*) exit 1
	esac
done

read_verilog_picorv32_opts=""
if $assume_picorv32_asserts; then
	read_verilog_picorv32_opts="-formal -norestrict -assume-asserts"
fi


yosys_script="
	verilog_defines -D RISCV_FORMAL
	verilog_defines -D RISCV_FORMAL_NRET=1
	verilog_defines -D RISCV_FORMAL_XLEN=32
	verilog_defines -D RISCV_FORMAL_BMC_DEPTH=$n
	verilog_defines -D RISCV_FORMAL_INSN_VH=\"../insns/insn_${insn}.vh\"
	verilog_defines -D RISCV_FORMAL_CHANNEL_IDX=0
	read_verilog ../../checks/rvfi_macros.vh

	read_verilog $read_verilog_picorv32_opts ../../../picorv32/picorv32.v
	read_verilog -formal insncheck.v ../../checks/rvfi_insn_check.v
	prep -nordff -top testbench
"

case "$solver" in
	bmc3_aig)
		yosys_script="$yosys_script
			flatten
			setattr -unset keep
			delete -output
			memory_map; opt -full; techmap
			setundef -zero; opt -fast
			abc -g AND -fast;; stat
			write_aiger -zinit insncheck_${insn}.aig
		"
		solver_cmd="yosys-abc -c 'read_aiger insncheck_${insn}.aig; fold; strash; bmc3 -F $((n+5)) -v'"
		;;
	bmc3_blif)
		yosys_script="$yosys_script
			miter -assert -flatten testbench miter
			hierarchy -top miter
			setattr -unset keep
			memory_map; opt -full; techmap
			opt -fast; abc -fast;; stat
			write_blif insncheck_${insn}.blif
		"
		solver_cmd="yosys-abc -c 'read_blif insncheck_${insn}.blif; undc; strash; zero; bmc3 -F $((n+5)) -v'"
		;;
	*)
		yosys_script="$yosys_script
			write_smt2 -wires insncheck_${insn}.smt2
		"
		solver_cmd="yosys-smtbmc -s $solver -t $((n+5)) --dump-vcd output.vcd insncheck_${insn}.smt2"
		;;
esac

set -ex
yosys -p "$yosys_script"
eval "$solver_cmd"
