#!/bin/bash

shopt -s expand_aliases
source .bash_aliases

# gather
UTXOS=$(btc-cli -rpcwallet=perf-legacy listunspent 1 999999999 [] true '{"minimumAmount":0.00002000,"maximumAmount":0.00002000}')
COUNT=$(echo $UTXOS | jq '.[] | .txid' | wc -l)
until [ $COUNT -lt 1 ]
do
    i=0
    until [ $COUNT -lt $i ]
    do
        echo $i of $COUNT
        btc-cli --rpcwallet=perf-legacy walletpassphrase "foo" 1000000
        ADDR=$(btc-cli --rpcwallet=perf-legacy getnewaddress $i)
        UTXO=$(echo $UTXOS | jq .[$i])
        ((i=i+1))
        UTXO2=$(echo $UTXOS | jq .[$i])
        ((i=i+1))
        INPUT1={\"txid\":$(echo $UTXO | jq .txid),\"vout\":$(echo $UTXO | jq -r .vout)}
        INPUT2={\"txid\":$(echo $UTXO2 | jq .txid),\"vout\":$(echo $UTXO2 | jq -r .vout)}
        TX=$(btc-cli --rpcwallet=perf-legacy createrawtransaction [$INPUT1,$INPUT2] [{\"$ADDR\":0.00002000}])
        SIGNED_TX=$(btc-cli --rpcwallet=perf-legacy signrawtransactionwithwallet $TX | jq -r .hex)
        rval=$(btc-cli sendrawtransaction $SIGNED_TX)
    done
    UTXOS=$(btc-cli -rpcwallet=perf-legacy listunspent 1 999999999 [] true '{"minimumAmount":0.00002000,"maximumAmount":0.00002000}')
    COUNT=$(echo $UTXOS | jq '.[] | .txid' | wc -l)
done