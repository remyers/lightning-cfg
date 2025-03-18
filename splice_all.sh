shopt -s expand_aliases
source .bash_aliases

function run_test {
    scripts/reset_all_nodes.sh >& /dev/null
    rm -r .bitcoin/regtest >& /dev/null
    scripts/start_bitcoin.sh >& /dev/null
    bob-clightning >& /dev/null &
    alice-eclair >& /dev/null &
    sleep 15
    mkdir -p results/$1
    rm results/$1/*
    ./scripts/$1.sh >& results/$1/$1.log
    alice-eclair-cli stop & bob-clightning-cli stop; btc-cli stop >& /dev/null
    sleep 5
    echo `date +%Y-%m-%dT%H:%M:%S` "Test $1 completed, copying logs to results/$1"
    mv .eclair/alice/eclair.log results/$1/ >> results/$1/$1.log
    mv .lightning/bob/regtest/cln.log results/$1/ >> results/$1/$1.log
}


# run all the splice test scripts and copy logs for later analysis
declare -a tests=("splice" "splice_rbf" "splice_reestablish" "splice_reestablish1" "splice_reestablish2" "splice_reestablish3" "splice_reestablish4" "splice_reestablish5" "splice_reestablish6")
for test in "${tests[@]}"; do
  echo `date +%Y-%m-%dT%H:%M:%S` "Running test: $test"
  run_test $test
done 
