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
check_funds

echo == Alice pays invoice for 50000 sats to Bob
export INVOICEA1=$(bob-clightning-cli invoice 50000000 test1 test1 | jq -r .bolt11)
export INVOICE_ID=$(alice-eclair-cli payinvoice --invoice=$INVOICEA1)
echo Invoice Id: $INVOICE_ID
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funds 450000000 50000000
echo [bob] invoice is: $(bob-clightning-cli listinvoices | jq -re '.invoices[0].status')

echo == Alice initiates splice-in of 15001 sat with Bob, Alice disconnects before Bob receives their tx_complete and commit_sig
echo == Test: "Disconnection with one side sending commit_sig"
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=15001 >& /dev/null
sleep 10
alice-eclair-cli connect --nodeId=$BOB_ID
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_log "our peer aborted the splice attempt" 1
check_funding_txid
check_funds 450000000 50000000

echo == Alice initiates splice-in of 15002 sat with Bob, Alice disconnects before sending their commit_sig
echo == Test: "Disconnection with both sides sending commit_sig"
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=15002 >& /dev/null
sleep 10
alice-eclair-cli connect --nodeId=$BOB_ID
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
sleep 10
check_log "received sig for batch of size=1 for fundingTxId" 1

btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
check_funding_txid
check_funds 465002000 50000000

echo == Finished
alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop >& /dev/null