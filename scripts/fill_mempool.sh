#!/bin/bash

# bitcoind -daemon -datadir=.bitcoin

shopt -s expand_aliases
source .bash_aliases

# fan out
COUNT=$(btc-cli -rpcwallet=perf-legacy listunspent 1 999999999 [] true '{"minimumAmount":0.03}' | wc -l)
until [ $COUNT -lt 10 ]
do
    echo $loop: $COUNT
    for i in $(seq $COUNT)
    do
        btc-cli --rpcwallet=perf-legacy walletpassphrase "foo" 1000000
        ADDR=$(btc-cli --rpcwallet=perf-legacy getnewaddress)
        MANY={\"$ADDR\":0.00002000}
        for i in {1..1000}
        do
            ADDR=$(btc-cli --rpcwallet=perf-legacy getnewaddress $i)
            MANY=$MANY,{\"$ADDR\":0.00002000}
        done
        UTXOS=$(btc-cli -rpcwallet=perf-legacy listunspent 1 999999999 [] true '{"minimumAmount":0.03}')
        INPUT1={\"txid\":$(echo $UTXOS | jq .[0].txid),\"vout\":$(echo $INPUT | jq -r .[0].vout)}
        TX=$(btc-cli --rpcwallet=perf-legacy createrawtransaction [$INPUT1] [$MANY])
        FUNDED_TX=$(btc-cli --rpcwallet=perf-legacy fundrawtransaction $TX | jq -r .hex)
        SIGNED_TX=$(btc-cli --rpcwallet=perf-legacy signrawtransactionwithwallet $FUNDED_TX | jq -r .hex)
        btc-cli sendrawtransaction $SIGNED_TX
    done
    btc-cli generatetoaddress 1 $ADDR
    COUNT=$(btc-cli -rpcwallet=perf-legacy listunspent 1 999999999 [] true '{"minimumAmount":0.03}' | wc -l)
done