#!/bin/bash
# 
# Common functions for splice tests

shopt -s expand_aliases
source .bash_aliases

function print_version {
    echo Alice/eclair: `alice-eclair-cli getinfo | jq -r .version`
    echo Bob/lightningd: `bob-clightning-cli --version`
}

function alice_wait_for_state {
    state=$(alice-eclair-cli channels | jq -re '.[0].state')
    while [[ "$state" != "$1" && "$state" != "CLOSING" ]]; do
        state=$(alice-eclair-cli channels | jq -re '.[0].state')
        sleep 5
    done
    if [[ "$state" == "CLOSING" ]]; then
        echo "Alice is closing"
        alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop
        exit 1
    fi
}

function bob_wait_for_state {
    state=$(bob-clightning-cli listfunds | jq -re '.channels[0].state')
    while [[ "$state" != "$1" && "$state" != "AWAITING_UNILATERAL" ]]; do
        state=$(bob-clightning-cli listfunds | jq -re '.channels[0].state')
        sleep 5
    done

    if [[ "$state" == "AWAITING_UNILATERAL" ]]; then
        echo "Bob is closing"
        alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop
        exit 1
    fi
}

function check_funding_txid {
    count=0

    while [ $count -eq 0 ] || [ "$bob_funding_txid" != "$alice_funding_txid" ] && [ $count -lt 5 ]; do
        bob_funding_txid=$(bob-clightning-cli listfunds | jq -re '.channels[0].funding_txid')
        alice_funding_txid=$(alice-eclair-cli channel --channelId=$CHANNEL_ID | jq -re '.data.commitments.active[]|select(.localFunding.status == "confirmed")|.localFunding.txid')
        count=$((count + 1))
        sleep 5
    done
    
    if [ "$bob_funding_txid" != "$alice_funding_txid" ]; then
        echo "Funding TXIDs do not match!"
        echo "Bob: $bob_funding_txid"
        echo "Alice: $alice_funding_txid"
    else
        confirmed=$(alice-eclair-cli channel --channelId=$CHANNEL_ID | jq -re '.data.commitments.active[]|select(.localFunding.status == "confirmed")|.fundingTxIndex')
        echo "Confirmed funding index: $confirmed"
        unconfirmed=$(alice-eclair-cli channel --channelId=$CHANNEL_ID | jq -re '.data.commitments.active[]|select(.localFunding.status == "unconfirmed")|.fundingTxIndex')
        echo "Unconfirmed funding index: $unconfirmed"
        echo "Funding TXID is $bob_funding_txid"
    fi
}

function check_funds {

    count=0
    while [ $count -eq 0 ] || [ $bob_to_local -ne $alice_to_remote ] || [ $alice_to_local -ne $bob_to_remote ] && [ $count -lt 5 ]; do
        bob_channels=$(bob-clightning-cli listpeerchannels | jq -re --arg channel_id $CHANNEL_ID '.channels[]|select(.channel_id == $channel_id )')
        bob_to_local=$(echo "$bob_channels" | jq -re '.to_us_msat')
        bob_to_remote=$(($(echo "$bob_channels" | jq -re '.total_msat') - $bob_to_local))

        alice_channel=$(alice-eclair-cli channel --channelId=$CHANNEL_ID | jq -re '.data.commitments.active[]|select(.localFunding.status == "confirmed")|.localCommit.spec')
        alice_to_local=$(echo "$alice_channel" | jq -re '.toLocal')
        alice_to_remote=$(echo "$alice_channel" | jq -re '.toRemote')
        sleep 5
        count=$((count + 1))
    done

    if { [ -n "$1" ] && [ "$alice_to_local" -ne "$1" ]; } || { [ -n "$2" ] && [ "$bob_to_local" -ne "$2" ]; }; then
        echo "Channel balance amounts do not match"
        echo "Alice to local: $alice_to_local != $1"
        echo "Alice to remote: $alice_to_remote"
        echo "Bob to_local: $bob_to_local != $2"
        echo "Bob to_remote: $bob_to_remote"
    elif [ $bob_to_local -ne $alice_to_remote ] || [ $alice_to_local -ne $bob_to_remote ]; then
        echo "Channel balance amounts do not match!"
        echo "Alice to local: $alice_to_local"
        echo "Alice to remote: $alice_to_remote"
        echo "Bob to_local: $bob_to_local"
        echo "Bob to_remote: $bob_to_remote"
    else
        echo "Channel balance amounts match."
        echo "to_alice: $alice_to_local"
        echo "to_bob: $bob_to_local"
    fi
}

function check_log {
    count=0
    while ! grep -m $2 -q "$1" .eclair/alice/eclair.log || [ $count -lt 5 ]; do
        sleep 5
        count=$((count + 1))
    done

    if grep -q "$1" .eclair/alice/eclair.log; then
        echo "Log check passed: $1 (x$2)"
    else
        echo "Log check failed: $1 (x$2)"
    fi
}