#!/bin/bash

shopt -s expand_aliases
source .bash_aliases

BALANCE=$(btc-cli --rpcwallet=$1 getbalance)
BC_LINE_LENGTH=9999
AMOUNT=$(echo "scale=8;($BALANCE-1)/$3" | bc)
echo "create/move $3 UTXOs of $AMOUNT BTC from $1 to $2"
ADDR=$(btc-cli --rpcwallet=$2 getnewaddress)
MANY=\"$ADDR\"
for i in $(seq $3)
do
    ADDR=$(btc-cli --rpcwallet=$2 getnewaddress $i)
    MANY=$MANY,{\"$ADDR\":0$AMOUNT}
done
btc-cli --rpcwallet=$1 -named sendall recipients=[$MANY] fee_rate=1
btc-cli generatetoaddress 1 $ADDR