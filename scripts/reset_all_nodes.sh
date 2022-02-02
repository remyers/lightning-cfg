#!/bin/bash

# kill eclair nodes
pkill -f alice
pkill -f bob
pkill -f carol
pkill -f dave

# remove files
(cd .eclair && ./reset_nodes.sh)
(cd .lightning && ./reset_nodes.sh)
(cd .lnd && ./reset_nodes.sh)
