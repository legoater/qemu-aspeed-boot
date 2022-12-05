#!/bin/bash
#
# boot QEMU Aspeed machines using a flash or eMMC image checking
# network and poweroff
#
# This work is licensed under the terms of the GNU GPL version 2. See
# the COPYING file in the top-level directory.

me=${0##*/}

qemu_prefix="/usr"
root_dir="."
quiet=
dryrun=
linux_quiet=
step="null"
extra_args="null"
config="./aspeed-images.json"

default_machines="ast2500-evb ast2600-evb"

PASSED="[32mPASSED[0m"
FAILED="[31mFAILED[0m"

sdk_kernel_args="\
systemd.mask=org.openbmc.HostIpmi.service \
systemd.mask=xyz.openbmc_project.Chassis.Control.Power@0.service \
systemd.mask=modprobe@fuse.service \
systemd.mask=rngd.service \
systemd.mask=obmc-console@ttyS2.service "

usage()
{
    cat <<EOF
$me 2.0

Usage: $me [OPTION] <machine> ...

Known values for OPTION are:

    -h|--help		display this help and exit
    -q|--quiet		all outputs are redirected to a logfile per machine
    -Q|--linux-quiet	Add 'quiet' to Linux parameters
    -p|--prefix	<DIR>	install prefix of QEMU binaries. Defaults to "$qemu_prefix".
    -r|--root <DIR>	top directory for FW images. Defaults to "$root_dir".
    -c|--config	<FILE>	JSON file list FW images to run. Defaults to "$config".
    -s|--step <STEP>	Stop test at step: FW, Linux, login
    -n|--dry-run	trial run

Default machines are:

    $default_machines

EOF
    exit 1;
}

# Requirements
for cmd in jq expect; do
    if ! command -v $cmd &> /dev/null; then
	echo "$me: Please install '$cmd' command"
	exit 1
    fi
done

options=`getopt -o hqQp:r:s:nc: -l help,quiet,linux-quiet,root:,prefix:,step:,dry-run,config: -- "$@"`
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
	-Q|--linux-quiet)	linux_quiet=1; shift 1;;
	-p|--prefix)	qemu_prefix="$2"; shift 2;;
	-r|--root)	root_dir="$2"; shift 2;;
	-s|--step)	step="$2"; shift 2;;
	-n|--dry-run)	dryrun=1; shift 2;;
	-c|--config)    config="$2"; shift 2;;
	--)		shift 1; break ;;
	*)		break ;;
    esac
done

qemu="$qemu_prefix/bin/qemu-system-arm"
if [ ! -f "$qemu" ]; then
    echo "$me: no QEMU binaries in \"$qemu_prefix\" directory"
    exit 1
fi

image_dir="$root_dir/images"
if [ ! -d "$image_dir" ]; then
    echo "$me: unknown \"$image_dir\" directory for firmware images"
    exit 1
fi

spawn_qemu()
{
    local machine=$1
    local image=$2
    local timeout=$3
    local poweroff=$4
    local stop_step=$5

    # TODO: should "mmc" be a field in the test definition ?
    case "$image" in
	*mmc*)
	    drive_args="-drive file=$image,format=qcow2,if=sd,id=sd0,index=2"
	    if [ "$machine" == "ast2600-evb" ]; then
		machine="${machine},boot-emmc=true"
	    fi
	    ;;
	*)
	    drive_args="-drive file=$image,format=raw,if=mtd"
	    ;;
    esac

    qemu_cmd="$qemu -M ${machine}"
    qemu_cmd="$qemu_cmd $drive_args -nic user"
    qemu_cmd="$qemu_cmd -serial stdio -nodefaults -nographic -snapshot"

    if [ -n "$dryrun" ]; then
	return 0
    fi

    if [ "$poweroff" == "null" ]; then
	poweroff="poweroff";
    fi

    if [ -n "$linux_quiet" ]; then
	case "$image" in
	    *sdk*)
		kernel_args="quiet $sdk_kernel_args"
		;;
	    *)
		kernel_args="quiet"
		;;
	esac
    fi

    if [[ "$step" != "null" ]]; then
	stop_step=$step
    fi

    # TODO: catch network pattern on all images

    expect - <<EOF 2>&3
set timeout $timeout

proc check_step {STEP} {
    if { [ string compare $stop_step \$STEP ] == 0 } {
       exit 0
    }
}

proc error {MSG} {
    puts -nonewline stderr "\$MSG"
}

proc info {MSG} {
    puts -nonewline stderr "\$MSG"
}

spawn $qemu_cmd
expect {
    "U-Boot 20"           { info "FW "; exp_continue }
    "Hit any key to stop autoboot" {
                            if { [ string compare "$kernel_args" "null" ] != 0 } {
			        send "\r"
		                send "setenv bootargs \\\${bootargs} $kernel_args\r"
		                send "boot\r"
                            }
                            exp_continue
			  }
    "Starting kernel ..." { check_step "FW"
                            exp_continue
                          }

    "Linux version "      { info "Linux "; exp_continue }
    "/init as init"       { check_step "Linux" 
                            info "/init "; exp_continue
                          }

    "lease of 10.0.2.15"  { info "net "; exp_continue }
    "Network is Online"   { info "net "; exp_continue }

    timeout               { error "TIMEOUT"; exit 1 }
    "Kernel panic"        { error "PANIC";   exit 2 }
    "BUG: soft lockup - CPU" {
                            error "STALL";   exit 3 }
    "self-detected stall on CPU" {
                            error "STALL";   exit 3 }
    "illegal instruction" { error "SIGILL";  exit 4 }
    "Segmentation fault"  { error "SEGV";    exit 5 }
    "login:"              { check_step "login"
                            info "login " }
}
send "root\r"
expect {
    timeout               { error "TIMEOUT"; exit 1 }
    "Password:"           { send "0penBmc\r"; exp_continue }
    "#"
}
send "$poweroff\r"
expect {
    timeout               { error "TIMEOUT"; exit 1 }
    "shutdown-sh#"        { info "poweroff"; exit 0 }
    "System halted"       { info "poweroff"; exit 0 }
    "Restarting system"   { info "poweroff"; exit 0 }
    "Power down"          { info "poweroff"; exit 0 }
}
expect -i $spawn_id eof
EOF
}

tests_machines=${*:-"$default_machines"}

exec 3>&1

for m in $tests_machines; do
    logfile="${m}.log"

    rm -f $logfile

    #
    # Array of struct defining the tests to run 
    #
    # @machine: the QEMU target machine
    # @image: the relative path of the FW image (flash of eMMC). The top
    #         directory being ./images
    # @timeout: maximum expected duration of the test
    # @poweroff: custom poweroff command
    # @stop_step: Optional (for activation only)
    # @excluded: do not run the test
    #
    jq -c ".[] | select(.machine==\"$m\")" $config | while read entry; do
	for field in machine image timeout poweroff stop_step excluded; do
	    eval $field=\""$(echo $entry | jq -r .$field)"\"
	done

	if [ "$excluded" == "yes" ]; then
	    continue;
	fi

	if [ -n "$quiet" ]; then
	    exec 1>>$logfile 2>&1
	fi

	echo -n "$machine - $image : " >&3

	image_path="$image_dir/$machine/$image"
	if [ ! -f "$image_path" ]; then
	    echo "invalid image"  >&3
	    continue;
	fi

	start=$(date +%s)
	spawn_qemu $machine $image_path $timeout "$poweroff" $stop_step &&
	    pass=$PASSED || pass=$FAILED
	end=$(date +%s)
	echo " $pass ($(($end-$start))s)" >&3
    done
done
