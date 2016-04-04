#!/bin/bash
#  File: rundst.sh
#  Author: simplex
#  Created: 2016-03-24
#  Last Update: 2016-04-04
#  Notes:

#######################################################
# 
# Configurable parameters of the script
#

# Directory where to install the dedicated server.
install_dir="$HOME/Documents/dontstarve/server"

# Command used to launch steamcmd. It may be a path to the steamcmd.sh
# script, as long as that script is made executable.
steamcmd=steamcmd

# Directory where DST's savedata is stored.
dontstarve_dir="$HOME/.klei/DoNotStarveTogether"

# Directory where Steam is installed. If this optional entry is set, the Steam
# runtime will be used to run the dedicated servers.
steamroot="$HOME/.steam/steam"

# Number of lines to store in the Lua console's history.
histsize=128

# Prefix for running the dedicated server binary under the Steam runtime. Use
# this to export LD_LIBRARY_PATH in case you lack system wide installations of
# some libraries and cannot rely on the Steam runtime.
# 
# This can also be the path to a wrapper script doing the exporting.
#
# Set to () to disable it.
bin_prefix=()

# Command used to invoke rlwrap, used to provide true line-oriented editing
# support for the dedicated server's command line Lua console.
#
# Unset it to disable rlwrap usage.
rlwrap_cmd=rlwrap



#######################################################
#
# Basic text UI utilities, using ANSI escape codes.
# We only use these if stdout is bound to a terminal.
# 

if [[ -t 1 ]]; then
	NORMAL=$'\e[0m'
	BOLD=$'\e[1m'

	RED=$'\e[31m'
	GREEN=$'\e[32m'
	YELLOW=$'\e[33m'
	BLUE=$'\e[34m'
	MAGENTA=$'\e[35m'
	CYAN=$'\e[36m'

	GREENBOLD=$'\e[32;1m'
fi

MASTER_SHARD_COLOR=$GREEN
SLAVE_SHARD_COLORS=($CYAN $YELLOW $RED $MAGENTA "" $BLUE)

TAB=$'\t'
HALFSOFTTAB='  '
SOFTTAB="${HALFSOFTTAB}${HALFSOFTTAB}"

INDENT0_5="${HALFSOFTTAB}"
INDENT="$SOFTTAB"
INDENT1_5="${INDENT}${INDENT0_5}"
INDENT2="${INDENT}${INDENT}"


#######################################################
#
# lib
#

function fail() {
    echo "${RED}${BOLD}Error${NORMAL}:" "$@" >&2
    exit 1
}

function warn() {
	echo "${MAGENTA}${BOLD}Warning${NORMAL}:" "$@" >&2
}


function subdirectories() {
	local name=$(basename "$1")
	find "$1" -maxdepth 1 -type d -a \( -name "$name" -o -printf '%f\n' \)
}

function get_cluster_witness() {
	echo -n "$dontstarve_dir/$1/cluster.ini"
}

function get_shard_witness() {
	echo -n "$dontstarve_dir/$1/$2/server.ini"
}

function cluster_has_shard() {
	[[ -e "$(get_shard_witness "$1" "$2")" ]]
	return $?
}

function is_cluster_master_shard() {
	local witness="$(get_shard_witness "$1" "$2")"
	[[ -r "$witness" ]] \
		&& grep -q -wi -m 1 'is_master[[:space:]]*=[[:space:]]*true' "$witness"
	return $?
}

# Receives (1 + n) arguments, where the first is the cluster name, and the ones
# following that are names of potential shards in that cluster (by potential, I
# mean they mean or may not exist).
#
# Outputs the list (line by line) with the master shard in the front. In case
# of multiple master shards, discards the ones after the first (with a warning
# message).
function sort_shards() {
	local mastername
	local maybe_mastername
	local slavenames=()

	for s in "${@:2}"; do
		if is_cluster_master_shard "$1" "$s"; then
			#echo "got master shard $s" >&2
			if [[ -z "$mastername" ]]; then
				mastername="$s"
			else
				warn "Multiple master shards ('$mastername' and '$s')."\
					"Ignoring the second one."
			fi
		elif [[ -z "$maybe_mastername" && "${s,,}" == master ]]; then
			maybe_mastername="$s"
		else
			slavenames+=("$s")
		fi
	done

	if ! [[ -z "$mastername" ]]; then
		echo "$mastername"
	fi
	if ! [[ -z "$maybe_mastername" ]]; then
		echo "$maybe_mastername"
	fi
	for s in "${slavenames[@]}"; do
		echo "$s"
	done
}

function shards_of() {
	local ret_shards=()

	for s in $(subdirectories "$dontstarve_dir/$1"); do
		if cluster_has_shard "$1" "$s"; then
			ret_shards+=("$s")
		fi
	done

	sort_shards "$1" "${ret_shards[@]}"
	return $?
}

# Uses case-insensitive lookup to find a match of a string in a list of
# strings. If found, the match from the list is echo'ed (in its original
# casing). The function's return code also indicated whether a match was found
# (0 is success).
function list_ilookup() {
	local needle="${1,,}"

	for x in "${@:2}"; do
		if [[ "${x,,}" == "$needle" ]]; then
			echo "$x"
			return 0
		fi
	done

	return 1
}

function check_list() {
	local listname="$1"
	shift
	local needle="$1"
	shift

	if ! list_ilookup "$needle" "$@" >/dev/null; then
		fail "Unable to find '$needle' in list '$listname'"
	fi
}

function check_for_file() {
    if [[ ! -e "$1" ]]; then
        fail "Missing file: $1"
    fi
}

function check_for_cmd() {
	if ! which "$1" >/dev/null; then
		fail "Missing command: $1"
	fi
}

#######################################################
# 
# Argument processing
#


args=()
serveropts=()

unset FORCE
unset NO_MORE_OPTIONS

function process_option() {
	if [[ -z "$NO_MORE_OPTIONS" ]]; then
		case "$1" in
			"-f")
				FORCE=1
				return
				;;
			"--")
				NO_MORE_OPTIONS=1
				return
				;;
			*)
				;;
		esac
	fi
	serveropts+=("$1")
}

for arg in "$@"; do
	if [[ "$arg" == -* ]]; then
		process_option "$arg"
	else
		args+=("$arg")
	fi
done

cluster_name="${args[0]}"

#######################################################

function usage() {
	cat <<EOS
Usage: $0 [options...] [--] [server-options...] <cluster-name> [shards...]
	 | $0 update

Launches a Don't Starve Together dedicated server cluster, or updates a Don't
Starve Together dedicated server installation with steamcmd.
	
In the first form, launches a given cluster. If no shard name is specified, all
shards in the given cluster are launched; otherwise, precisely shards listed
are launched. The following options are recognized:

  -f	If a shard whose name was explicitly given does not exist, create it
		with default configurations instead of raising an error.

Any other argument starting with a '-' differing from the ones listed above, or
any argument starting with a '-' after the optional positional parameter '--',
is interpreted as a server option and passed verbatim to the invocation of the
dedicated server executable for every shard.

In the second form, installs or updates the dedicated server.
EOS

	echo ""

	echo "${BOLD}Available clusters${NORMAL}:"
	for c in "${clusters[@]}"; do
		echo "${INDENT}${GREENBOLD}${c}${NORMAL}"
		echo "${INDENT1_5}${BOLD}Shards${NORMAL}:"
		for s in $(shards_of "$c"); do
			echo -e "${INDENT2}${CYAN}${s}${NORMAL}"
		done
	done
}

#######################################################

if [[ "$cluster_name" == update ]]; then
	check_for_cmd "$steamcmd"
	exec "$steamcmd" +force_install_dir "$install_dir" +login anonymous +app_update 343050 validate +quit
fi

#######################################################

check_for_file "$dontstarve_dir"

clusters=()
for subdir in $(subdirectories "$dontstarve_dir"); do
	if [[ -e "$dontstarve_dir/$subdir/cluster.ini" ]]; then
		clusters+=("$subdir")
	fi
done

if [[ -z "$cluster_name" ]]; then
	usage >&2
	exit 0
fi

#check_for_file "$(get_cluster_witness "$cluster_name")"
check_list "clusters" "$cluster_name" "${clusters[@]}"

#######################################################

shards=()
for s in $(shards_of "$cluster_name"); do
	shards+=("$s")
done

function normalize_shardname() {
	local norm1="$(list_ilookup "$1" "${shards[@]}")"
	if [[ -z "$norm1" ]]; then
		echo -n "$1"
	else
		echo -n "$norm1"
	fi
}

#######################################################

chosen_shardnames=()
for s in "${args[@]:1}"; do
	chosen_shardnames+=("$(normalize_shardname "$s")")
done

if [[ ${#chosen_shardnames[@]} -eq 0 ]]; then
	if [[ ${#shards[@]} -eq 0 ]]; then
		fail "The cluster '$cluster_name' has no shards."
	fi

	chosen_shardnames=("${shards[@]}")
else
	chosen_shardnames=($(sort_shards "$cluster_name" "${chosen_shardnames[@]}"))
fi

if [[ ${#chosen_shardnames[@]} -eq 0 ]]; then
	fail "Logic error."
fi

#######################################################

# Exports environment variables to smooth out dependency hell.
#
# Primarily, it attempts to hook to the Steam runtime.
function setupEnvironment() {
	if [[ -z "$steamroot" ]]; then return; fi

	local PREFIX="$steamroot/ubuntu12_32/steam-runtime/i386/"
	if [[ -d "$PREFIX" ]]; then
		echo "${BOLD}Hooking to the Steam runtime.${NORMAL}"
		local RUNTIME="$PREFIX/usr/lib/i386-linux-gnu:$PREFIX/lib/i386-linux-gnu"
		if [[ ! -z "$LD_LIBRARY_PATH" ]]; then
			LD_LIBRARY_PATH="$RUNTIME:$LD_LIBRARY_PATH"
		else
			LD_LIBRARY_PATH="$RUNTIME"
		fi
		export LD_LIBRARY_PATH
	else
		warn "Steam runtime prefix doesn't exist or isn't a directory:" \
			$'\n'"$PREFIX"
	fi
}

#######################################################

check_for_file "$dontstarve_dir/$cluster_name/cluster_token.txt"

for s in "${chosen_shardnames[@]}"; do
	if [[ -z "$FORCE" ]]; then
		#check_for_file "$(get_shard_witness "$cluster_name" "$s")"
		check_list "shards" "$s" "${shards[@]}"
	else
		mkdir -p "$dontstarve_dir/$cluster_name/$s"
	fi
done

check_for_file "$install_dir/bin"

cd "$install_dir/bin" || fail 

#######################################################

run_shard=("${bin_prefix[@]}")
run_shard+=(./dontstarve_dedicated_server_nullrenderer)
run_shard+=(-console)
run_shard+=(-cluster "$cluster_name")

# PIDs
self_pid=$$
children_pids=()

# Index of the current slave shard being processed.
slave_shard_idx=0

function basic_start_shard() {
	echo "${BOLD}Starting shard $1...${NORMAL}"

	local MYPID=$BASHPID

	local PRECMDS=()

	if [[ $MYPID -ne $self_pid ]]; then
		PRECMDS+=("exec")
	fi

	if [[ $$ -eq $self_pid && ! -z "$rlwrap_cmd" ]]; then
		local histfile="$dontstarve_dir/$cluster_name/$1/tty_console_hist.txt"
		local prompt="$2> "
		touch "$histfile"
		PRECMDS+=("$rlwrap_cmd" -R -H "$histfile" -s $histsize -f . -S "$prompt")
	fi

	local fullcmd=("${PRECMDS[@]}" "${run_shard[@]}" -monitor-parent-process 
		"$MYPID" -shard "$1" "${serveropts[@]}")

	echo "${BOLD}Running${NORMAL} '${fullcmd[@]}'..."
	"${fullcmd[@]}"
}

function prettify_shardname() {
	local COLOR
	if is_cluster_master_shard "$cluster_name" "$1"; then
		COLOR=${MASTER_SHARD_COLOR}
	else
		COLOR=${SLAVE_SHARD_COLORS[$slave_shard_idx]}
	fi
	echo -n "${COLOR}${BOLD}$1${NORMAL}"
}

function start_single_shard() {
	local name="$(prettify_shardname "$1")"
	(local MYPID=$BASHPID ;
	 basic_start_shard "$1" "$name" > >(sed -e "s/^/$name($MYPID):  /")
	 )
}

function start_slave_shard() {
	local name="$(prettify_shardname "$1")"
	(local MYPID=$BASHPID ;
	 basic_start_shard "$1" "$name" > >(sed -e "s/^/$name($MYPID):  /")
	 ) &
	children_pids+=($!)
	slave_shard_idx=$(( $slave_shard_idx + 1 ))
}

function start_shard_list() {
	for shard in "${@:2}"; do
		start_slave_shard "$shard"
	done
	start_single_shard "$1"
}

#

clear
clear

setupEnvironment

#

start_shard_list "${chosen_shardnames[@]}"
if [[ ${#children_pids[@]} -gt 0 ]]; then
	kill "${children_pids[@]}" >/dev/null 2>&1
	wait "${children_pids[@]}"
fi

echo "${BOLD}Finished shutting down cluster '$cluster_name'.${NORMAL}"
