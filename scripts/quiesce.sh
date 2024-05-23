#!/bin/bash
# This script tests quiescence compatibility with LND using a modified version of Eclair that
# allows Alice to add an htlc even after receiving stfu from Bob - this simulates a race condition
# between Bob sending stfu and Alice sending UpdateAddHtlc. LND is modified to add a 'quiesce' command
# which forces it to enter quiescence and send `stfu`.
#
# lnd: 3805f97 https://github.com/remyers/lnd/tree/2024-03-stfu-remyers
# eclair: 0.10.1-SNAPSHOT-8f592e5 https://github.com/remyers/eclair/commits/quiescence-interop-testing
# set -x

shopt -s expand_aliases
source .bash_aliases

ALICE_ID=$(alice-eclair-cli getinfo | jq -r .nodeId)
BOB_ID=$(bob-lnd-cli getinfo | jq -r .identity_pubkey)
MINER=$(btc-cli getnewaddress)

echo Alice/Eclair is $ALICE_ID
echo Bob/LND is $BOB_ID

echo Alice connects to Bob 
alice-eclair-cli connect --nodeId=$BOB_ID
echo Alice opens channel to Bob
alice-eclair-cli open --nodeId=$BOB_ID --fundingSatoshis=500000 --fundingFeeBudgetSatoshis=2000
btc-cli generatetoaddress 6 `btc-cli getnewaddress` >& /dev/null
CHANNEL_POINT=`bob-lnd-cli listchannels | jq -r .channels[0].channel_point`
echo Bob creates an invoice
INVOICE=`bob-lnd-cli addinvoice | jq -r .payment_request`
echo Bob sends stfu to Alice
bob-lnd-cli quiesce $CHANNEL_POINT && echo "Bob waits 90 sec for invoice to be settled" && sleep 90 && bob-lnd-cli listinvoices | jq --arg invoice "$INVOICE" -e '.invoices[]|select(.payment_request == $invoice)' | (grep "state" || { echo "Invoice not settled!"; exit 1; }) &
echo Alice pays the invoice before responding to Bob with stfu
alice-eclair-cli payinvoice --invoice=$INVOICE --amountMsat=1000000