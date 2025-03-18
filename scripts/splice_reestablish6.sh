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
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
export CHANNEL_ID=$(alice-eclair-cli channels | jq -re '.[0]|select(.state == "NORMAL")|.channelId')
echo channelId is $CHANNEL_ID
check_funding_txid
check_funds 500000000 0

echo == Test: "Disconnection after exchanging tx_signatures and both sides send commit_sig for channel update"
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=15008 >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
sleep 10

echo Alice sends update_add_htlc and disconnects before sending commit_sigs to Bob
export INVOICEA1=$(bob-clightning-cli invoice 100000000 test1 test1 | jq -r .bolt11)
echo Invoice Id: $(alice-eclair-cli payinvoice --invoice=$INVOICEA1)
check_log "Ignoring commit sigs for interop test: Disconnection after exchanging tx_signatures and both sides send commit_sig for channel update" 1

echo Alice resends update_add_htlc and commit_sig after reconnecting
check_log "IN msg=RevokeAndAck" 4

btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
sleep 10
alice_wait_for_state "NORMAL"
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 415008000 100000000

echo == Finished
stop_nodes