#!/usr/bin/env bash

source 'lib/term_colors.sh'
source 'lib/parseopts.sh'
source 'lib/output_format.sh'

# http://stackoverflow.com/a/185900
tmpfiles=()

cleanup() {
    msg "Cleaning stuff up..."
    msg "Bye bye..."
    rm -rf "${tmpfiles[@]}"
}

trap cleanup SIGINT
trap cleanup SIGKILL

usage() {
    echo "usage: tshark-remote.sh [options]"
    echo ""
    echo "Options:"
    echo "  -r <host>, --remote <host>   Remote host (\"user@remote\") to connect to"
    echo "  -i <dev>, --interface <dev>  Interface to sniff (can0, eth0, ...)"
    echo "  -f <path>, --file <path>     Do not log to stdout; creates a pcapng file"
    echo "  -V, --version                Show version number (generated by Git)"
    echo "  -h, --help                   Show this page and exit"
}

version() {
    echo "tshark-remote.sh $(git describe --always --dirty)"
}

OPT_SHORT='r:i:f:hV'
OPT_LONG=('remote:' 'help' 'version')
if ! parseopts "$OPT_SHORT" "${OPT_LONG[@]}" -- "$@"; then
    exit 1
fi
set -- "${OPTRET[@]}"
unset OPT_SHORT OPT_LONG OPTRET

while true; do
	case "$1" in
        -r|--remote)      shift; REMOTE=$1;;
        -i|--interface)   shift; INTERFACE=$1;;
        -f|--file)        shift; FILE=${1%.*}.pcapng;;  # Strip possibly wrong extensions

        -h|--help)        usage; exit 0 ;; # E_OK
        -V|--version)     version; exit 0 ;; # E_OK

        --)               OPT_IND=0; shift; break 2;;
    esac
    shift
done

if [[ -z ${REMOTE+x} ]]; then
    error "No remote specified!"
    msg "Leaving..."
    exit 1
fi

if [[ -z ${INTERFACE+x} ]]; then
    error "No interface specified!"
    msg "Leaving..."
    exit 1
fi

msg "Starting remote capturing on ${REMOTE}; ${INTERFACE} at $(date)"

# https://wiki.wireshark.org/CaptureSetup/Pipes
FIFO=$(mktemp -u)
mkfifo $FIFO
tmpfiles+=($FIFO)
tshark_args="-i ${FIFO}"

if [[ ! -z ${FILE+x} ]]; then
    msg "Writing to file: ${FILE}"
    tshark_args+=" -F pcapng -W n -w ${FILE}"
fi

tshark $tshark_args &

dumpcap_args="-P -w - -i ${INTERFACE}"

# If we want to capture something that is not a can interface, we need to
# exclude our own SSH traffic. This is just a workaround, maybe the situation
# improves in the future...
if [[ ! $INTERFACE =~ can[0-9]+ ]]; then
    dumpcap_args+=" -f 'not tcp port 22'"
fi

ssh $REMOTE "dumpcap ${dumpcap_args}" > $FIFO
