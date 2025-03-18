#!/bin/bash
# 
# versions tested: 
#   bitcoind: git checkout tags/v28.1
#   clightning: ddustin "ddustin/splice_interop_final_(probably)" branch
#   eclair: remyers "splicing-official-interop" branch
#
# before running this script, run:
#  scripts/reset_all_nodes.sh
#  rm -r .bitcoin/regtest
#  scripts/start_bitcoin.sh
#  alice-eclair
#  bob-clightning

shopt -s expand_aliases
source .bash_aliases

# load common testing functions
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/common.sh"
print_version

export CLN_DEBUG_SPLICE=false
export ALICE_ID=$(alice-eclair-cli getinfo | jq -r .nodeId)
export BOB_ID=$(bob-clightning-cli getinfo | jq -r .id)
export BOB_ADDR=$(bob-clightning-cli newaddr | jq -r .bech32)
export MINER=$(btc-cli getnewaddress)

echo fund Bob wallet
btc-cli sendtoaddress $BOB_ADDR 1

echo Alice/Eclair is $ALICE_ID
echo Bob/CLightning is $BOB_ID

echo Alice connects to Bob: $(alice-eclair-cli connect --uri=$BOB_ID@127.0.0.1:9737)
echo Alice opens channel to Bob
alice-eclair-cli open --nodeId=$BOB_ID --fundingSatoshis=500000 --fundingFeeBudgetSatoshis=3000 --announceChannel=false >& /dev/null
sleep 10
btc-cli generatetoaddress 12 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
export CHANNEL_ID=$(alice-eclair-cli channels | jq -re '.[0]|select(.state == "NORMAL")|.channelId')
echo channelId is $CHANNEL_ID
check_funding_txid
check_funds 500000000 0

echo == Test: "Disconnection with concurrent splice_locked"
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=15006 >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
sleep 10

echo Alice disconnects before sending splice_locked to Bob
btc-cli generatetoaddress 8 $(btc-cli getnewaddress) >& /dev/null
check_log "Not sending our splice_locked for interop test: Disconnection with concurrent splice_locked" 1
sleep 10

echo Bob sends splice_locked, but Alice ignores it and disconnects
btc-cli generatetoaddress 4 $(btc-cli getnewaddress) >& /dev/null
check_log "Ignoring splice_locked for interop test: Disconnection with concurrent splice_locked" 1

echo Alice sends update_add_htlc at the same time as Bob re-sends splice_locked
check_log "peer is connected" 3

echo Alice sends update_add_htlc immediately when reconnected to Bob
export INVOICEA1=$(bob-clightning-cli invoice 100000000 test1 test1 | jq -r .bolt11)
echo Invoice Id: $(alice-eclair-cli payinvoice --invoice=$INVOICEA1)
check_log "OUT msg=UpdateAddHtlc" 1
check_log "OUT msg=CommitSig" 8

echo Alice does not process splice_locked from Bob immediately
check_log "Deferring processing splice_locked from peer for interop test" 1
check_log "setting remoteFundingStatus=Locked" 6
sleep 10
echo Alice processes splice_locked from Bob after she sends update_add_htlc and commit_sig: this is fine.

alice_wait_for_state "NORMAL"
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 415006000 100000000

echo == Finished
alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop >& /dev/null