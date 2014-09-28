#!/usr/bin/env mksh

#
# NetOps - Shell micro-framework for automated deployments over SSH
#
# Copyright 2014
#	Olivier Duclos <olivier.duclos@gmail.com>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un‐
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided “AS IS” and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person’s immediate fault when using the work as intended.

set -eu
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

usage() {
	echo "usage: ${0##*/} [-d] [-m] [-h] [-v] <rule_name>"
	echo "options:
	-d		debug mode: print only
	-m		monoprocess: execute only 1 op at a time
	-h		show this help
	-v		show version number"
	exit $1
}

version() {
	echo "NetOps v0.01"
	exit $1
}

# Options
typeset -i debug=0 mono=0

# Operations
typeset -i last_op=-1
typeset -a ops_name ops_doc ops_targets ops_needs ops_code


die() {
	echo "*** error ***" "$@" >&2
	exit 1
}

info() {
	local op="$1"
	shift
	echo "[$op]" "$@"
}

find_id() {
	local name="$1" i=-1
	while (( ++i <= last_op )); do
		if [ ${ops_name[$i]} = "$name" ]; then
			echo $i
			return
		fi
	done

	die "unknown operation '$name'"
}

show_ops() {
	echo "Available commands:"
	local i=-1
	while (( ++i <= last_op )); do
		printf "    %-15s %s\n" "${ops_name[$i]}" "${ops_doc[$i]:-}"
	done
}

run_op() {
	local op_name="$1" caller=${2:-unset}
	local op_id targets target dep code

	info "$op_name" "starting"

	# Get the requested operation id
	op_id=$(find_id "$op_name")

	# Execute dependencies
	for dep in ${ops_needs[$op_id]:-unset}; do
		[ "$dep" != "unset" ] || break

		# Sanity check
		if [ "$dep" = "$op_name" ]; then
			die "op '$op_name' depends on itself"
		fi

		# Naive circular dependency detection
		if [ "$caller" = "$dep" ]; then
			die "circular dependency detected " \
			    "between $caller and $op_name"
		fi

		run_op "$dep" "$op_name"
	done

	# Lauch the op on each target server
	targets=${ops_targets[$op_id]:-localhost}
	# uniq
	targets=$(tr ' ' '\n' <<< ${targets} | sort -u | tr '\n' ' ')

	for target in ${targets}; do
		code=${ops_code[$op_id]:-unset}
		if [ "$code" = "unset" ]; then
			info "$op_name" "nothing to do"
			continue
		fi

		if ((debug == 1)); then
			info "$op_name" ssh $target ${code}
		else
			ssh $target ${code} &
			((mono == 0)) || wait
		fi
	done

	wait

	info "$op_name" "success"
}

### PUBLIC API

name() {
	last_op=$((++last_op))
	ops_name[$last_op]="$1"
}

doc() {
	ops_doc[$last_op]="$@"
}

target() {
	ops_targets[$last_op]="$1"
}

targets() {
	ops_targets[$last_op]="$@"
}

needs() {
	ops_needs[$last_op]="$@"
}

code() {
	local var line
	while read -r line; do var+=$line; done
	ops_code[$last_op]="$var"
}

codel() {
	ops_code[$last_op]="$@"
}

main() {
	local ch op_id target

	while getopts "dmhv" ch; do
		case $ch in
		(d)    debug=1
		       ;;
		(m)    mono=1
		       ;;
		(h)    usage 0
		       ;;
		(v)    version 0
		       ;;
		(*)    echo "unknown option '$ch'" >&2
		       usage 1
		       ;;
		esac
	done
	shift $((OPTIND - 1))

	if (($# > 1)); then
		usage 1
	elif (($# < 1)); then
		show_ops
		exit 0
	fi

	run_op "$1"
}

### END OF PUBLIC API
