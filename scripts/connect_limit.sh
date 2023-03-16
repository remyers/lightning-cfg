export ALICE_ID=$(alice-eclair-cli getinfo | jq -r .nodeId)
bob-eclair-cli connect --uri=$ALICE_ID@localhost:9735
bob-eclair-cli open --nodeId=$ALICE_ID --fundingSatoshis=1000000
carol-eclair-cli connect --uri=$ALICE_ID@localhost:9735