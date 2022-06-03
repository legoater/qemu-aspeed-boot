#!/bin/bash
#
# Run a test doing a basic boot with network and poweroff for each
# Aspeed machines supported in QEMU using a flash image
#
# This work is licensed under the terms of the GNU GPL version 2. See
# the COPYING file in the top-level directory.

me=${0##*/}

qemu_prefix=/usr
quiet=
image_dir=./images/

default_machines="ast2500-evb ast2600-evb"

PASSED="[32mPASSED[0m"
FAILED="[31mFAILED[0m"

usage()
{
    cat <<EOF
$me 1.0

Usage: $me [OPTION] <board ...>

Known values for OPTION are:

    -h|--help			display this help and exit
    -q|--quiet			all outputs are redirected to a logfile per machine
    -p|--prefix	<DIR>		install prefix of QEMU binaries. Defaults to "$qemu_prefix".
    -i|--image	<DIR>		top directory for FW images. Defaults to "$image_dir".

Default machines are:

    $default_machines

EOF
    exit 1;
}

options=`getopt -o hqp: -l help,quiet,prefix: -- "$@"`
if [ $? -ne 0 ]
then
        usage
fi
eval set -- "$options"

while true
do
    case "$1" in
	-h|--help)	usage ;;
	-q|--quiet)	quiet=1; shift 1;;
	-p|--prefix)	qemu_prefix="$2"; shift 2;;
	-i|--image)	image_dir="$2"; shift 2;;
	--)		shift 1; break ;;
	*)		break ;;
    esac
done

qemu="$qemu_prefix/bin/qemu-system-arm"
if [[ ! -f "$qemu" ]]; then
    echo "$me: no QEMU binaries in \"$qemu_prefix\" directory"
    exit 1
fi

if [ ! -d "$image_dir" ]; then
    echo "$me: unknown \"$buildroot_dir\" directory for firmware images"
    exit 1
fi


spawn_qemu()
{
    local drive_args
    local machine_args
    
    local machine=$1
    local logfile="${machine}.log"
    local fwdir="$image_dir/$machine/default"
    local net_args="-nic user"

    case "$machine" in
	*evb)
	    timeout=40
	    machine_args="-M ${machine}"
	    drive_args="-drive file=${fwdir}/flash.img,format=raw,if=mtd"
	    ;;
	*)
 	    echo "invalid machine \"$machine\"";
	    exit 1;
    esac 

    qemu_cmd="$qemu $machine_args $drive_args $net_args"
    qemu_cmd="$qemu_cmd -serial stdio -nodefaults -nographic -snapshot"

    if [ -n "$quiet" ]; then
	exec 1>$logfile 2>&1
    fi

    expect \
	-c "spawn $qemu_cmd" \
	-c "set timeout $timeout" \
	-c 'expect "U-Boot 20"           { puts -nonewline stderr "FW "; \
					   exp_continue } \
		   "Linux version "      { puts -nonewline stderr "Linux "; \
					   exp_continue } \
		   "/init as init"       { puts -nonewline stderr "/init "; \
					   exp_continue } \
		   "lease of 10.0.2.15"  { puts -nonewline stderr "net "; \
					   exp_continue } \
		   "Network is Online"   { puts -nonewline stderr "net "; \
					   exp_continue } \
		   timeout               { puts -nonewline stderr "TIMEOUT"; exit 1 } \
		   "Kernel panic"        { puts -nonewline stderr "PANIC";   exit 2 } \
		   "illegal instruction" { puts -nonewline stderr "SIGILL";  exit 3 } \
		   "Segmentation fault"  { puts -nonewline stderr "SEGV";    exit 4 } \
		   "login:"		 { puts -nonewline stderr "login " }' \
	-c 'send "root\r"' \
	-c 'expect timeout      { puts -nonewline stderr "TIMEOUT"; exit 1 } \
		   "#"' \
	-c 'send "poweroff\r"' \
	-c 'expect timeout        { puts -nonewline stderr "TIMEOUT"; exit 1 } \
		   "shutdown-sh#" { puts -nonewline stderr "DONE"; exit 0 }  \
		   "halted" 	  { puts -nonewline stderr "DONE"; exit 0 }  \
		   "Power down"   { puts -nonewline stderr "DONE"; exit 0 }' \
	-c "expect -i $spawn_id eof" 2>&3
}

tests_machines=${*:-"$default_machines"}

exec 3>&1

for m in $tests_machines; do
    echo -n "$m : " >&3
    spawn_qemu $m && pass=$PASSED || pass=$FAILED
    echo " ($pass)" >&3
done
