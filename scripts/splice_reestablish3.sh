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
alice-eclair-cli open --nodeId=$BOB_ID --fundingSatoshis=500000 --fundingFeeBudgetSatoshis=3000 >& /dev/null
sleep 10
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
export CHANNEL_ID=$(alice-eclair-cli channels | jq -re '.[0]|select(.state == "NORMAL")|.channelId')
echo channelId is $CHANNEL_ID
check_funding_txid
check_funds 500000000 0

echo == Alice initiates splice-in of 15005 sat, but disconnects before Bob receives her tx_signatures and new update commit_sigs
echo == Test: "Disconnection with both sides sending tx_signatures and channel updates"
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=15005 >& /dev/null
sleep 10
alice_wait_for_state "NORMAL"
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
sleep 10
export INVOICEA1=$(bob-clightning-cli invoice 15005000 test1 test1 | jq -r .bolt11)
echo Invoice Id: $(alice-eclair-cli payinvoice --invoice=$INVOICEA1)
tail -n 150 -f  .eclair/alice/eclair.log | grep -m 1 --line-buffered -o 'Not sending our tx_signatures for interop test: Disconnection with both sides sending tx_signatures and channel updates'
tail -n 150 -f  .eclair/alice/eclair.log | grep -m 1 --line-buffered -o 'Not sending our update_add_htlc for interop test: Disconnection with both sides sending tx_signatures and channel updates'
tail -n 150 -f  .eclair/alice/eclair.log | grep -m 1 --line-buffered -o 'Not sending our commit sigs for interop test: Disconnection with both sides sending tx_signatures and channel updates'
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
check_funds 484995000 15005000
echo [bob] invoice is: $(bob-clightning-cli listinvoices | jq -re '.invoices[0].status')

echo Alice resends tx_signatures, update_add_htlc and commit_sig after reconnecting
tail -n 150 -f .eclair/alice/eclair.log | grep -m 1 --line-buffered -o 'IN msg=RevokeAndAck' >& /dev/null

btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL"
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 500000000 15005000

echo == Finished
alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop >& /dev/null