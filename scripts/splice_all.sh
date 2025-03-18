#!/bin/bash
# This script runs all the splice tests and copies the logs to the results directory for later analysis.

shopt -s expand_aliases
source .bash_aliases

# load common testing functions
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
. "$DIR/common.sh"

function run_test {
    scripts/reset_all_nodes.sh >& /dev/null
    rm -r .bitcoin/regtest >& /dev/null
    scripts/start_bitcoin.sh >& /dev/null
    alice-eclair >& /dev/null &
    bob-clightning >& /dev/null &
    sleep 15
    mkdir -p results/$1
    rm results/$1/*
    ./scripts/$1.sh >& results/$1/$1.log
    stop_nodes
    sleep 5
    echo `date +%Y-%m-%dT%H:%M:%S` "Test $1 completed, copying logs to results/$1"
    mv .eclair/alice/eclair.log results/$1/ >> results/$1/$1.log
    mv .lightning/bob/regtest/cln.log results/$1/ >> results/$1/$1.log
}

# run all the splice test scripts and copy logs for later analysis
declare -a tests=("splice" "splice_rbf" "splice_reestablish1" "splice_reestablish2" "splice_reestablish3" "splice_reestablish4" "splice_reestablish5" "splice_reestablish6" "splice_reestablish7")
for test in "${tests[@]}"; do
  echo `date +%Y-%m-%dT%H:%M:%S` "Running test: $test"
  run_test $test
done 

# Look for any errors in the logs 
# note: ignore known parse errors in cln logs and the channel funding error in splice_rbf.sh
find ./results -name "*.log" -print0 | xargs -0 grep -i error | grep -i -v parse
