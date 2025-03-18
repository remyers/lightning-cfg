#!/bin/bash
# 
# versions tested: 
#   bitcoind: git checkout tags/v28.1
#   clightning: git clone https://github.com/ddustin/lightning.git -b "ddustin/splice_interop_final_(probably)"
#   eclair: "splicing-official" -> "splicing-official-interop"
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
# Successful single splices
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

echo == Alice initiates splice-in of 15000 sat with Bob
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=15000 >& /dev/null
sleep 10
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 515000000 0

echo == Alice pays invoice for 100000 sats to Bob
export INVOICEA1=$(bob-clightning-cli invoice 100000000 test1 test1 | jq -r .bolt11)
export INVOICE_ID=$(alice-eclair-cli payinvoice --invoice=$INVOICEA1)
echo Invoice Id: $INVOICE_ID
sleep 10

echo == Bob pays invoice for 50000 sats to Alice
export INVOICEB1=$(alice-eclair-cli createinvoice --amountMsat=50000000 --description=test1 | jq -r .serialized)
echo Invoice Id: $(bob-clightning-cli pay $INVOICEB1 | jq -r .payment_hash)
sleep 10

alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funds 465000000 50000000
echo [bob] invoice is: $(bob-clightning-cli listinvoices | jq -re '.invoices[0].status')

echo == Bob initiates splice-in of 10000 sats with Alice
bob-clightning-cli dev-splice "wallet -> 20000sat; 10000sat -> $ALICE_ID:0" false false $CLN_DEBUG_SPLICE >& /dev/null
sleep 10
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 465000000 60000000

echo == Bob initiates splice-out of 16000 sats with Alice
bob-clightning-cli dev-splice "$CHANNEL_ID -> 16000sat" false false $CLN_DEBUG_SPLICE >& /dev/null
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 465000000 44000000

echo == Alice initiates splice-out of 20000 sat with Bob
alice-eclair-cli spliceout --channelId=$CHANNEL_ID --amountOut=20000 --scriptPubKey=76a9146c772e9cf96371bba3da8cb733da70a2fcf2007888ac >& /dev/null
sleep 10
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 444814000 44000000


echo == Alice initiates splice-in of 30000 sat with Bob, splice does not confirm
alice-eclair-cli splicein --channelId=$CHANNEL_ID --amountIn=30000 >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
check_funding_txid
check_funds 444814000 44000000

echo == Alice pays invoice for 25000 sats to Bob
export INVOICEA1=$(bob-clightning-cli invoice 25000000 test2 test2 | jq -r .bolt11)
export INVOICE_ID=$(alice-eclair-cli payinvoice --invoice=$INVOICEA1)
echo Invoice Id: $INVOICE_ID
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_AWAITING_SPLICE"
check_funds 419814000 69000000
echo [bob] invoice is: $(bob-clightning-cli listinvoices | jq -re '.invoices[0].status')

echo == Alice confirms Splice-in of 30000 sat
btc-cli generatetoaddress 9 $(btc-cli getnewaddress) >& /dev/null
sleep 10
alice_wait_for_state "NORMAL" 
bob_wait_for_state "CHANNELD_NORMAL"
check_funding_txid
check_funds 449814000 69000000

echo == Alice pays invoice from Bob after splices
export INVOICEA3=$(bob-clightning-cli invoice 100000000 test3 test3 | jq -r .bolt11)
echo Invoice Id: $(alice-eclair-cli payinvoice --invoice=$INVOICEA3)

echo == Finished
alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop >& /dev/null