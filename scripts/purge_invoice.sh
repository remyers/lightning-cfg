#!/bin/bash

# This script tests that expired invoices are purged
# Must add to .eclair/carol/eclair.conf:
#   eclair.purge-expired-invoices.interval=1 minutes

shopt -s expand_aliases
source .bash_aliases

ALICE_ID=$(alice-eclair-cli getinfo | jq -r .nodeId)
BOB_ID=$(bob-eclair-cli getinfo | jq -r .nodeId)
CAROL_ID=$(carol-eclair-cli getinfo | jq -r .nodeId)

echo Alice is $ALICE_ID
echo Bob is $BOB_ID
echo Carol is $CAROL_ID

echo Opening channels between Alice and Bob...
alice-eclair-cli connect --uri=$BOB_ID@localhost:9736
alice-eclair-cli open --nodeId=$BOB_ID --fundingSatoshis=600000

echo Opening channels between Bob and Carol...
bob-eclair-cli connect --uri=$CAROL_ID@localhost:9737
bob-eclair-cli open --nodeId=$CAROL_ID --fundingSatoshis=500000

echo Generating a few blocks to confirm channels...
MINER=$(btc-cli getnewaddress)
btc-cli generatetoaddress 10 $MINER

echo Awaiting confirmations...
sleep 30

echo Channels confirmed:
bob-eclair-cli channels | jq '.[] | {shortChannelId: .data.shortChannelId, capacity: .data.channelUpdate.htlcMaximumMsat}'

echo Generating invoices...
INVOICE1=$(carol-eclair-cli createinvoice --amountMsat=250000000 --description="will expire" --expireIn=60 | jq .serialized)
INVOICE2=$(carol-eclair-cli createinvoice --amountMsat=200000000 --description="will not expire" | jq .serialized)

echo Carol has two invoices:
carol-eclair-cli listinvoices | jq ".[] | {invoice:.serialized, paymentHah:.paymentHash, description:.description}"

echo Waiting for first invoice to be purged by Carol
sleep 120

echo Carol now has one invoice
carol-eclair-cli listinvoices | jq ".[] | {invoice:.serialized, paymentHah:.paymentHash, description:.description}"

echo Paying first invoice fails with "expired invoice"
alice-eclair-cli payinvoice --amountMsat=250000000 --blocking --invoice=$INVOICE1

echo Paying second invoice succeeds
alice-eclair-cli sendtoroute --amountMsat=200000000 --nodeIds=$ALICE_ID,$BOB_ID,$CAROL_ID --finalCltvExpiry=16 --invoice=$INVOICE2
sleep 10

echo Checking payment status for invoice 1
PAYMENT_HASH1=$(alice-eclair-cli parseinvoice --invoice=$INVOICE1 | jq .paymentHash)
echo "Alice: " `alice-eclair-cli getsentinfo --paymentHash=$PAYMENT_HASH1`
echo "Carol: " `carol-eclair-cli getreceivedinfo --paymentHash=$PAYMENT_HASH1`

echo Checking payment status for invoice 2
PAYMENT_HASH2=$(alice-eclair-cli parseinvoice --invoice=$INVOICE2 | jq .paymentHash)
echo "Alice:"
alice-eclair-cli getsentinfo --paymentHash=$PAYMENT_HASH2 | jq ".[] | {paymentHash: .paymentHash, description:.invoice.description, status:.status.type}"
echo "Carol:"
carol-eclair-cli getreceivedinfo --paymentHash=$PAYMENT_HASH2 | jq "{paymenthash:.invoice.paymentHash, description:.invoice.description, status:.status.type}"