#!/bin/bash

# This script starts Bitcoin and generates a block.
# This makes sure Bitcoin isn't in IBD mode.

shopt -s expand_aliases
source .bash_aliases

bitcoind -daemon -datadir=.bitcoin

sleep 3

# http://bip32.org/

# master
export XPRV="tprv8ZgxMBicQKsPd7Uf69XL1XwhmjHopUGep8GuEiJDZmbQz6o58LninorQAfcKZWARbtRtfnLcJ5MQ2AtHcQJCCRUcMRvmDUjyEmNUWwx8UbK"

# BIP-84 m/84'/1'/0' (created with private key via bip32.org)
# export XPUB="tpubDCzQCHCjoUGLiNo7fLL3HGxLMyTU8sxe1UiPmGNoRGxYkEuhh7AZMFgvdjWmug3VMw54xvVCrC69Jp5R55CowxxfvgGQJbdHFCpf7sCupVW"
export XPUB="tpubDCxRWKVAyTh7SCDrwF55VWCNsTWEAcP6erxVQtxajXZB3XDai7rHHusoHGy12BiRzqQt6nz59caVGczBsh4UHTwqdGRnXHgnLDJNcdQGaEC"

# main addresses: m/84h/1h/0h/* (created with private key via bip32.org) 
export DESCRIPTOR0="wpkh([00000000/84h/1h/0h]$XPUB/0/*)#f9lq250a"
btc-cli getdescriptorinfo $DESCRIPTOR0

# change addresses: m/84'/1'/0'/1/* (created with private key via bip32.org)
export DESCRIPTOR1="wpkh([00000000/84h/1h/0h]$XPUB/1/*)#c36phpl9"
btc-cli getdescriptorinfo $DESCRIPTOR1

# create wallet
btc-cli createwallet eclair true true "" false true false 

# import test descriptor
export descriptors_json="[{\"desc\":\"$DESCRIPTOR0\",\"active\":true,\"timestamp\":\"now\",\"internal\":false},{\"desc\":\"$DESCRIPTOR1\",\"active\":true,\"timestamp\":\"now\",\"internal\":true}]"
btc-cli -rpcwallet="eclair" importdescriptors $descriptors_json
# get test descriptor wallet info
btc-cli -rpcwallet="eclair" getwalletinfo

# add some coins to addresses derived from our descriptor
btc-cli generatetodescriptor 1 "wpkh([00000000/84h/1h/0h]$XPUB/0/1)"
btc-cli generatetodescriptor 1 "wpkh([00000000/84h/1h/0h]$XPUB/0/2)"
btc-cli generatetodescriptor 1 "wpkh([00000000/84h/1h/0h]$XPUB/0/3)"
btc-cli generatetodescriptor 100 "wpkh([00000000/84h/1h/0h]$XPUB/0/4)"

btc-cli -rpcwallet="eclair" getbalances

# create raw transaction
btc-cli -rpcwallet="eclair" createrawtransaction "[]" "{\"bcrt1qafxa06jrrgnegwpytk0audlg24jm60srmyfr2x\":0.01}"
btc-cli -rpcwallet="eclair" decoderawtransaction "02000000000140420f0000000000160014ea4dd7ea431a279438245d9fde37e85565bd3e0300000000"

# fund it from descriptor UTXOs
btc-cli -rpcwallet="eclair" fundrawtransaction "02000000000140420f0000000000160014ea4dd7ea431a279438245d9fde37e85565bd3e0300000000"
btc-cli -rpcwallet="eclair" decoderawtransaction "02000000019d80e6dce52d542ea4307a343c12e0e5f9a58ffbd7f9bf5d4a83dc42652b24620000000000fdffffff0240420f0000000000160014ea4dd7ea431a279438245d9fde37e85565bd3e03a0be440200000000160014924fd0e6a69a8faeb28b39b063f19aed53905f6100000000"