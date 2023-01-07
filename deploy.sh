#!/bin/bash
forge test && forge create --rpc-url $MATIC_RPC_URL --constructor-args $OPS $OPERATOR --private-key $DEPLOYER_KEY veTetuRelocker --etherscan-api-key $ETHERSCAN_KEY --chain polygon --verify
