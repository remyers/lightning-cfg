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
#  scripts/start_bitcoin.sh; alice-eclair & bob-clightning &

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

echo fund Bob wallet with 1 BTC
btc-cli sendtoaddress $BOB_ADDR 1 >& /dev/null

echo Alice/Eclair is $ALICE_ID
echo Bob/CLightning is $BOB_ID

#
# Multiple splices with concurrent splice_locked
#

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

echo == Alice initiates splice-in of 30000 sat with Bob, splice does not confirm
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=30000 >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
check_funding_txid
check_funds 500000000 0

echo == Alice initiates RBF of splice, but aborts after Bob sends tx_accept_rbf
alice-eclair-cli rbfsplice --channelId=$CHANNEL_ID --targetFeerateSatByte=400 --fundingFeeBudgetSatoshis=100000 >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
check_funding_txid
check_funds 500000000 0

echo == Alice RBFs splice-in with Bob, RBF does not confirm
alice-eclair-cli rbfsplice --channelId=$CHANNEL_ID --targetFeerateSatByte=400 --fundingFeeBudgetSatoshis=200000 >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
check_funding_txid
check_funds 500000000 0

echo == Alice pays invoice for 25000 sats to Bob
export INVOICEA1=$(bob-clightning-cli invoice 25000000 test2 test2 | jq -r .bolt11)
export INVOICE_ID=$(alice-eclair-cli payinvoice --invoice=$INVOICEA1)
echo Invoice Id: $INVOICE_ID
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
check_funds 475000000 25000000
echo [bob] invoice is: $(bob-clightning-cli listinvoices | jq -re '.invoices[0].status')

echo == Alice confirms Splice-in RBF of 30000 sat
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 505000000 25000000

echo == Finished
alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop >& /dev/null