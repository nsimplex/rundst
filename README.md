# rundst

A script for running, installing and updating Don't Starve Together dedicated servers.

The main features of this script are:
* Automatic detection of clusters and shards
* Pretty printing of each shard's output, with each line preceded by the bold and uniquely colored shard's name, followed by its PID (process ids). Sending a `kill` command to a slave shard's PID will cause it to exit gracefully (i.e., properly saving and exiting the server). Sending a `kill` command to the master shard's PID will cause the whole cluster to exit gracefully.
* Sending EOF (Ctrl-D) over an empty input line in the terminal is translated into a `c_shutdown()` command for the master shard. This causes the whole cluster to exit gracefully.
* Extended editing support in the master shard's terminal Lua console via the GNU readline library.
    * Positional keys (arrows, Home, End, etc.) are supported when entering terminal input.
    * The Up/Down keys scroll through the saved command history (preserved between server invocations).
    * Ctrl-R provides reverse lookup on the command history.
    * Tab provides autocompletion based on the command history.
    * A prompt with the master shard name followed by "> " precedes command input.
* Support for easily installing/updating beta branches.

## Usage

First check the top part of the script, titled "Configurable parameters of the script", and adjust any parameters to fit your configurations and preferences.

Running the script with no arguments will print a usage message, followed by the list of clusters and their shards detected on your system. The usage message is printed below (though check the script's own output to make sure it is up to date):

    Usage: ./rundst.sh [options...] [--] [server-options...] <cluster-name> [shards...]
    	 | ./rundst.sh update [beta-branch] [beta-code]
    
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
    
    In the second form, installs or updates the dedicated server. If the optional
    'beta-branch' argument is given, installs/updates the DST beta branch with that
    name instead; if 'beta-code' is given, it is used as the password for a private
    beta.  If 'beta-branch' is absent but an environment variable called
    'DST_BETA_BRANCH' is set, that value is used for 'beta-branch'. Similarly,
    'beta-code' defaults to the value of the 'DST_BETA_CODE' environment variable.
    
### Installation

You are not required to install this script, as it may be run from any location. Nonetheless, a Makefile is provided such that `make install` or simply `make` will install the script on your system. The default install location is ~/bin, with the script being installed with its '.sh' extension removed. This may be changed by editing the Makefile, in particular the variables IDIR and RSRC.

Running `make uninstall` will uninstall the script from your system.
