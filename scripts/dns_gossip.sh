#!/bin/bash
# This script tests gossip between clightning and eclair of dns host names, Bolt PR #911.
#  
# 1) Add these lines to the files:
# /etc/hosts 
#   127.0.0.1       dnstest1.co.fr
#   127.0.1.1       dnstest2.co.fr
#   127.0.2.1       dnstest3.co.fr
#
# .eclair/alice/eclair.conf
#   eclair.server.public-ips=[dnstest1.co.fr]
#   close-on-offline-feerate-mismatch = false
#   feerate-tolerance {
#      ratio-low = 0.01 // will allow remote fee rates as low as 100th our local feerate when not using anchor outputs
#      ratio-high = 100.0 // will allow remote fee rates as high as 100 times our local feerate when not using anchor outputs
#   }
#
# .lightning/bob/config
#   bind-addr=127.0.1.1:9736
#   announce-addr=dnstest2.co.fr:9736
#   dev-fast-gossip
#
# .eclair/carol/eclair.conf
#   eclair.server.public-ips=[dnstest3.co.fr]
#   close-on-offline-feerate-mismatch = false
#   feerate-tolerance {
#      ratio-low = 0.01 // will allow remote fee rates as low as 100th our local feerate when not using anchor outputs
#      ratio-high = 100.0 // will allow remote fee rates as high as 100 times our local feerate when not using anchor outputs
#   }
#
# 2) Reset nodes
#  ./scripts/reset_all_nodes.sh
#
# 3) Start nodes:
#  alice-eclair & carol-eclair & bob-clightning >& bob-clightning.log &
#
# 3) Run this script...

# exit when any command fails
set -e

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

shopt -s expand_aliases
source .bash_aliases

ALICE_ID=$(alice-eclair-cli getinfo | jq -r .nodeId)
BOB_ID=$(bob-clightning-cli getinfo | jq -r .id)
CAROL_ID=$(carol-eclair-cli getinfo | jq -r .nodeId)
MINER=$(btc-cli getnewaddress)

echo Alice is $ALICE_ID
echo Bob is $BOB_ID
echo Carol is $CAROL_ID

echo Adding some Bitcoin to wallets...

BOB_ADDR=$(bob-clightning-cli newaddr bech32 | jq -r .bech32)
btc-cli sendtoaddress $BOB_ADDR 15 >& /dev/null

echo Generating a few blocks to confirm wallet balances...
btc-cli generatetoaddress 10 $MINER >& /dev/null
sleep 20

echo Opening channels between Alice and Bob...
alice-eclair-cli connect --uri=$BOB_ID@dnstest2.co.fr:9736 >& /dev/null
sleep 3
alice-eclair-cli open --nodeId=$BOB_ID --fundingSatoshis=300000 >& /dev/null
sleep 3
echo Opening channels between Bob and Carol...
bob-clightning-cli connect $CAROL_ID dnstest3.co.fr 9737 >& /dev/null
sleep 3
bob-clightning-cli fundchannel $CAROL_ID 300000 >& /dev/null
sleep 3

echo Generating a few blocks to confirm channels...
btc-cli generatetoaddress 10 $MINER >& /dev/null
sleep 3

echo Creating invoices...
ALICE_INVOICE_5_000=$(alice-eclair-cli createinvoice --amountMsat=5000000 --description="ALICE invoice1" --expireIn=600 | jq -r .serialized)
ALICE_INVOICE_10_000=$(alice-eclair-cli createinvoice --amountMsat=10000000 --description="ALICE invoice2" --expireIn=600 | jq -r .serialized)
BOB_INVOICE_10_000=$(bob-clightning-cli invoice 10000000 $RANDOM "BOB invoice1" | jq -r .bolt11)
BOB_INVOICE_5_000=$(bob-clightning-cli invoice  5000000 $RANDOM "BOB invoice2" | jq -r .bolt11)
CAROL_INVOICE_10_000=$(carol-eclair-cli createinvoice --amountMsat=10000000 --description="CAROL invoice1" --expireIn=600 | jq -r .serialized)
CAROL_INVOICE_20_000=$(carol-eclair-cli createinvoice --amountMsat=20000000 --description="CAROL invoice2" --expireIn=600 | jq -r .serialized)

echo Awaiting gossip sync...
START=$(date +%s)
while :; do if [ `alice-eclair-cli allchannels | grep shortChannelId | wc -l` -eq 2 ] && [ `carol-eclair-cli allchannels | grep shortChannelId | wc -l` -eq 2 ]; then break; fi; done
echo "Gossip sync took $(($(date +%s) - $START)) seconds"

echo Paying invoices...

# echo "ALICE [300,000 sat] : BOB   [0 sat]"
# echo "BOB   [300,000 sat] : CAROL [0 sat]"
# bob-clightning-cli listfunds | jq -r '.channels | .[] | .channel_sat'

echo "1. BOB -> CAROL [10,000]"
bob-clightning-cli pay $CAROL_INVOICE_10_000 | jq -r .status
sleep 5

# echo "ALICE [300,000 sat] : BOB   [0 sat]"
# echo "BOB   [290,000 sat] : CAROL [10,000 sat]"
# bob-clightning-cli listfunds | jq -r '.channels | .[] | .channel_sat'

echo "2. ALICE -> BOB [10,000]"
alice-eclair-cli payinvoice --invoice=$BOB_INVOICE_10_000 --blocking=true | jq -r .type
sleep 5

# echo "ALICE [290,000 sat] : BOB   [10,000 sat]"
# echo "BOB   [290,000 sat] : CAROL [10,000 sat]"
# bob-clightning-cli listfunds | jq -r '.channels | .[] | .channel_sat'

echo "3. CAROl -> BOB -> ALICE [5,000]"
carol-eclair-cli payinvoice --invoice=$ALICE_INVOICE_5_000 --blocking=true | jq -r .type
sleep 5

# echo "ALICE [295,000 sat] : BOB   [5,000 sat]"
# echo "BOB   [295,000 sat] : CAROL [5,000 sat]"
# bob-clightning-cli listfunds | jq -r '.channels | .[] | .channel_sat'

echo "4. ALICE -> BOB -> CAROL [20,000]"
alice-eclair-cli payinvoice --invoice=$CAROL_INVOICE_20_000 --blocking=true | jq -r .type
sleep 5

# echo "ALICE [275,000 sat] : BOB   [25,000 sat]"
# echo "BOB   [275,000 sat] : CAROL [25,000 sat]"
# bob-clightning-cli listfunds | jq -r '.channels | .[] | .channel_sat'

echo "5. BOB -> ALICE [10,000]"
bob-clightning-cli pay $ALICE_INVOICE_10_000 | jq -r .status
sleep 5

# echo "ALICE [285,000 sat] : BOB   [15,000 sat]"
# echo "BOB   [275,000 sat] : CAROL [25,000 sat]"
# bob-clightning-cli listfunds | jq -r '.channels | .[] | .channel_sat'

echo "6. CAROL -> BOB [5,000]"
carol-eclair-cli payinvoice --invoice=$BOB_INVOICE_5_000 --blocking=true | jq -r .type

# echo "ALICE [285,000 sat] : BOB   [15,000 sat]"
# echo "BOB   [280,000 sat] : CAROL [20,000 sat]"
# bob-clightning-cli listfunds | jq -r '.channels | .[] | .channel_sat'

echo All invoices paid
