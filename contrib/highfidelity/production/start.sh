#!/bin/sh

# Ensure that elementsd is running:
# If -reset is specified, wipe everything and start over.
# If the blocksigning key files aren't here, then we're hosed. Prompt for manual reset and stop.
# If we're already running, just exit, letting elementsd continue to run. (If you want to stop, just pkill elementsd.)
# Otherwise (e.g., after elementsd has been stopped):
#    start up with the blocksigning keys and,
#    IIF this is fresh, go ahead and mature the money and claim it.
#      (I.e., elementsd could be stopped (see above), and this script will restart it. If it is restarted "from scratch" (via -reset or some other way),
#       this cript ensures that we don't have unclaimed 21M laying around.)
# See elements.conf for rpc info.

HERE=`pwd`/`dirname $0`
DATA_DIR=$HERE
ELEMENTS_PATH=$HERE/../../../src
PRIVFILE=$HERE/blockpriv
PUBFILE=$HERE/blockpub

alias daemon="$ELEMENTS_PATH/elementsd -datadir=$DATA_DIR"
alias cli="$ELEMENTS_PATH/elements-cli -datadir=$DATA_DIR"

if [ "$1" = "-reset" ]; then
    echo Resetting all blockchain data and stashing new blocksigning keys.
    
    pkill elementsd  # stop any existing
    sleep 1
    rm -r $HERE/elementsregtest $PRIVFILE $PUBFILE
    daemon
    sleep 5  # can't talk to it during startup
    ADDR=$(cli getnewaddress)
    VALID=$(cli validateaddress $ADDR)
    echo $VALID | python3 -c "import sys, json; print(json.load(sys.stdin)['pubkey'])" > $PUBFILE
    cli dumpprivkey $ADDR > $PRIVFILE
    # For security, you cannot swap out blocksigner with old genesis block
    cli stop
    sleep 2
    rm -r $HERE/elementsregtest
    
elif [ ! -f $PUBFILE ] || [ ! -f $PRIVFILE ]; then
    echo ERROR: Missing key file. We cannot generate new keys with the old genesis block, so there is no option other than -reset.
    exit 1
fi

if pgrep elementsd; then
    echo Elements already running.
    exit 0
fi

PUBKEY=`cat $PUBFILE`
KEY=`cat $PRIVFILE`
SIGNBLOCKARG="-signblockscript=5121$(echo $PUBKEY)51ae"
daemon $SIGNBLOCKARG
sleep 5
cli importprivkey $KEY

if [ $(cli getblockcount) -lt 101 ]; then
    # Mine all blocks before others have a chance to connect
    for block in {1..101}; do
        HEX=$(cli getnewblockhex)
        SIGN=$(cli signblock $HEX)
        BLOCKRESULT=$(cli combineblocksigs $HEX '''["'''$SIGN'''"]''')
        SIGNBLOCK=$(echo $BLOCKRESULT | python3 -c "import sys, json; print(json.load(sys.stdin)['hex'])")
        cli submitblock $SIGNBLOCK
    done
    cli sendtoaddress $(cli getnewaddress) 21000000 "" "" true # transaction fee paid from amount
    cli getblockcount
fi
cli getbalance
    


