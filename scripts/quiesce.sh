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
alice-eclair-cli connect --uri=$BOB_ID@127.0.0.1:9736
echo Alice opens channel to Bob
alice-eclair-cli open --nodeId=$BOB_ID --fundingSatoshis=500000 --pushMsat=250000000 --fundingFeeBudgetSatoshis=3000
btc-cli generatetoaddress 9 `btc-cli getnewaddress` >& /dev/null
CHANNEL_POINT=`bob-lnd-cli listchannels | jq -r .channels[0].channel_point`
echo channel_point is $CHANNEL_POINT
CHANNEL_ID=`alice-eclair-cli channels | jq -re '.[]|select(.state == "NORMAL")|.channelId'`
echo channelId is $CHANNEL_ID

# test 1 and 2
echo Bob creates an invoice
INVOICE=`bob-lnd-cli addinvoice | jq -r .payment_request`
echo Bob sends stfu to Alice
bob-lnd-cli quiesce $CHANNEL_POINT && echo "Bob waits 90 sec for invoice to be settled" && sleep 90 && bob-lnd-cli listinvoices | jq --arg invoice "$INVOICE" -e '.invoices[]|select(.payment_request == $invoice)' | (grep "state" || { echo "Invoice not settled!"; exit 1; }) &
echo Alice pays the invoice before responding to Bob with stfu
alice-eclair-cli payinvoice --invoice=$INVOICE --amountMsat=1000000

# test 3
echo Alice creates invoices for Bob
INVOICEA1=`alice-eclair-cli createinvoice --description=invoice_1 | jq -r .serialized`
INVOICEA2=`alice-eclair-cli createinvoice --description=invoice_2 | jq -r .serialized`
INVOICEA3=`alice-eclair-cli createinvoice --description=invoice_3 | jq -r .serialized`
echo Bob sends payments to Alice, but Alice does not immediately pay them
bob-lnd-cli payinvoice --pay_req $INVOICEA1 --amt 2222 --force &
bob-lnd-cli payinvoice --pay_req $INVOICEA2 --amt 3333 --force &
bob-lnd-cli payinvoice --pay_req $INVOICEA3 --amt 4444 --force &
echo Bob sends stfu to Alice, Alice sends updates to Bob either before or after sending stfu
bob-lnd-cli quiesce $CHANNEL_POINT
alice-eclair-cli close --channelId=$CHANNEL_ID
btc-cli generatetoaddress 9 `btc-cli getnewaddress` >& /dev/null