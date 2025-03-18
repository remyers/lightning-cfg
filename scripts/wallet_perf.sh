#!/bin/bash

# This script creates a legacy wallet performs 100,000 transactions, 200,000 new addresses and
# then leaves 1000 utxos.
#
# rm -r .bitcoin/regtest
# bitcoind -daemon -datadir=.bitcoin

shopt -s expand_aliases
source .bash_aliases

# create perf legacy wallet
btc-cli createwallet "perf" false false "" false false

# create eclair/miner descriptor wallet
btc-cli createwallet "eclair"

MINER=$(btc-cli --rpcwallet=eclair getnewaddress)
btc-cli generatetoaddress 8 $MINER
ADDR=$(btc-cli --rpcwallet=perf getnewaddress)
btc-cli --rpcwallet=eclair -named sendall recipients=[\"$ADDR\"] fee_rate=1
btc-cli generatetoaddress 1 $MINER

echo "create 100,000 new blocks and UTXO sweep txs"
for i in {1..1} 
do
    ADDR=$(btc-cli --rpcwallet=perf getnewaddress)
    btc-cli --rpcwallet=perf -named sendall recipients=[\"$ADDR\"] fee_rate=1
    btc-cli --rpcwallet=perf getnewaddress
    btc-cli generatetoaddress 1 $MINER
done

echo "create 1000 UTXOs"
ADDR=$(btc-cli --rpcwallet=perf getnewaddress)
MANY=\"$ADDR\":1
for i in {1..1000}
do
    ADDR=$(btc-cli --rpcwallet=perf getnewaddress $i)
    MANY=$MANY,\"$ADDR\":1
done
btc-cli --rpcwallet=perf sendmany "" {$MANY} 
btc-cli generatetoaddress 1 $MINER
echo $(btc-cli -rpcwallet=perf listreceivedbyaddress 1 true | grep "txid" | wc -l) addresses
echo $(btc-cli -rpcwallet=perf listtransactions "*" 300000 | grep "wtxid" | wc -l) transactions
echo $(btc-cli -rpcwallet=perf listunspent | grep "txid" | wc -l) utxos

# btc-cli -rpcwallet=perf createrawtransaction [{"txid":"16592e51c066afbd7d8a734ca9977cf1c4b6c934be5dd095e69ade6be49b9808","vout":0}]
 [{"bcrt1qcddszume0dv4sn75hjx0fwdacs22fypre6dcj0":1}]

# (0.3 seconds) time btc-cli -rpcwallet=perf fundrawtransaction 020000000108989be46bde9ae695d05dbe34c9b6c4f17c97a94c738a7dbdaf66c0512e59160000000000fdffffff0100e1f50500000000160014c35b0173797b59584fd4bc8cf4b9bdc414a4902300000000
# (0.3 seconds) time btc-cli -rpcwallet=perf listunspent 
# (3-9 seconds) time btc-cli -rpcwallet=perf listreceivedbyaddress | grep "address" | wc -l  

# time btc-cli -rpcwallet=perf encryptwallet foo
