#!/bin/bash
#  File: rundst.sh
#  Author: simplex
#  Created: 2016-03-24
#  Last Update: 2016-03-24
#  Notes:

###
# Configurable parameters of the script
#

# Directory where to install the dedicated server.
install_dir="$HOME/Documents/dontstarve/server"

# Command used to launch steamcmd. It may be a path to the steamcmd.sh
# script, as long as that script is made executable.
steamcmd=steamcmd

# Directory where DST's savedata is stored.
dontstarve_dir="$HOME/.klei/DoNotStarveTogether"

# Number of lines to store in the Lua console's history.
histsize=128

#######################################################

# Basic text UI utilities

NORMAL=$'\e[0m'
BOLD=$'\e[1m'

RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
MAGENTA=$'\e[35m'
CYAN=$'\e[36m'

GREENBOLD=$'\e[32;1m'

MASTER_SHARD_COLOR=$GREEN
SLAVE_SHARD_COLORS=($YELLOW $CYAN $RED $MAGENTA "" $BLUE)

TAB=$'\t'

INDENT=$'    '
INDENT2="${INDENT}${INDENT}"

#######################################################

# lib

function subdirectories() {
	local name=$(basename "$1")
	find "$1" -maxdepth 1 -type d -a \( -name "$name" -o -printf '%f\n' \)
}

function shards_of() {
	for s in $(subdirectories "$dontstarve_dir/$1"); do
		if [[ -e "$dontstarve_dir/$1/$s/server.ini" ]]; then
			echo "$s"
		fi
	done
}

function fail() {
        echo "${RED}${BOLD}Error${NORMAL}:" "$@" >&2
        exit 1
}

function check_list() {
	local listname="$1"
	local needle="$2"
	
	for x in "${@:3}"; do
		if [[ "$x" == "$needle" ]]; then
			return
		fi
	done

	fail "Unable to find '$needle' in list '$listname'"
}

function check_for_file() {
    if [ ! -e "$1" ]; then
            fail "Missing file: $1"
    fi
}

function check_for_cmd() {
	if ! which "$1" >/dev/null; then
		fail "Missing command: $1"
	fi
}

function usage() {
	echo "Usage: $0 update | $0 <cluster-name> [shard]"
	
	echo ""
	echo "In the first form, installs or updates the dedicated server."
	echo "In the second form, launches a given cluster. If no shard name"
	echo "is specified, all shards in the given cluster are launched".
	echo ""

	echo "${BOLD}Available clusters${NORMAL}:"
	for c in "${clusters[@]}"; do
		echo "${INDENT}${GREENBOLD}${c}${NORMAL}"
		echo "${INDENT2}${BOLD}Shards${NORMAL}:"
		for s in $(shards_of "$c"); do
			echo -e "${INDENT2}${CYAN}${s}${NORMAL}"
		done
	done
}

#######################################################

clusters=()
for subdir in $(subdirectories "$dontstarve_dir"); do
	if [[ -e "$dontstarve_dir/$subdir/cluster.ini" ]]; then
		clusters+=("$subdir")
	fi
done

#######################################################

if [[ -z "$1" ]]; then
	usage >&2
	exit 0
fi

check_for_cmd "$steamcmd"

if [[ "$1" == update ]]; then
	exec "$steamcmd" +force_install_dir "$install_dir" +login anonymous +app_update 343050 validate +quit
fi

check_list clusters "$1" "${clusters[@]}"
cluster_name="$1"

shards=()
for s in $(shards_of "$cluster_name"); do
	shards+=("$s")
done

check_for_file "$dontstarve_dir/$cluster_name/cluster.ini"
check_for_file "$dontstarve_dir/$cluster_name/cluster_token.txt"
check_for_file "$dontstarve_dir/$cluster_name/Master/server.ini"
#check_for_file "$dontstarve_dir/$cluster_name/Caves/server.ini"

check_for_file "$install_dir/bin"

cd "$install_dir/bin" || fail 

run_shard=(./dontstarve_dedicated_server_nullrenderer)
run_shard+=(-console)
run_shard+=(-cluster "$cluster_name")

# PIDs
self_pid=$$
children_spawner_pid=
children_pids=()

(kill -STOP $BASHPID) &
mutex_pid=$!

function basic_start_shard() {
	echo "Starting shard $1..."

	local PRECMDS=()
	if [[ $BASHPID -eq $self_pid ]]; then
		local histfile="$dontstarve_dir/$cluster_name/$1/tty_console_hist.txt"
		PRECMDS+=(rlwrap -H "$histfile" -s $histsize)
	fi

	"${PRECMDS[@]}" "${run_shard[@]}" -monitor-parent-process $2 \
		-shard "$1"  | sed -u -e "s/^/$3($BASHPID):  /"
}

function start_single_shard() {
	local name="$1"
	local COLOR=${MASTER_SHARD_COLOR}
	local PREFIX="${COLOR}${BOLD}${name}${NORMAL}"

	basic_start_shard "${name}" $self_pid "$PREFIX"
}

function start_master_shard() {
	start_single_shard Master
}

shard_idx=0
function start_slave_shard() {
	local name="$1"
	local COLOR=${SLAVE_SHARD_COLORS[$shard_idx]}
	local PREFIX="${COLOR}${BOLD}${name}${NORMAL}"

	basic_start_shard "${name}" $self_pid "$PREFIX" &
	children_pids+=($!)
	shard_idx=$(( $shard_idx + 1 ))
}

if [[ -z "$2" ]]; then
	for shard in "${shards[@]}"; do
		if [[ "$shard" != Master ]]; then
			start_slave_shard "$shard"
		fi
	done

	start_master_shard
else
	check_list shards "$2" "${shards[@]}"
	start_single_shard "$2"
fi

echo "${BOLD}Shut dedicated server down.${NORMAL}"
