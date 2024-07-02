#!/bin/bash

cleanup() {
    echo "Cleaning up..."
    # Check if Anvil PID is set and if the process is running, then kill it
    if [ ! -z "$ANVIL_PID" ]; then
        if ps -p $ANVIL_PID >/dev/null; then
            echo "Killing Anvil (PID $ANVIL_PID)..."
            kill $ANVIL_PID
        fi
    fi
}

# Trap EXIT and ERR signals to call the cleanup function
# This ensures cleanup is performed on script exit or error
trap cleanup EXIT ERR

# Start Anvil and capture its output temporarily
anvil >anvil_logs.txt 2>&1 &
ANVIL_PID=$!
echo "Anvil started with PID $ANVIL_PID"

# Wait a few seconds to ensure Anvil has started and output private keys
sleep 5

export ETH_WALLET_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Build the project
echo "Building the project..."
cargo build

# Deploy the Counter contract
echo "Deploying the Counter contract..."
forge script --rpc-url http://localhost:8545 --broadcast script/Deploy.s.sol

# Extract the Toyken address
export TOYKEN_ADDRESS=$(jq -re '.transactions[] | select(.contractName == "ERC20") | .contractAddress' ./broadcast/Deploy.s.sol/31337/run-latest.json)
echo "ERC20 Toyken Address: $TOYKEN_ADDRESS"

# Mint Toyken to a specific address
echo "Minting Toyken to 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266...(self address)"
cast send --private-key $ETH_WALLET_PRIVATE_KEY --rpc-url http://localhost:8545 $TOYKEN_ADDRESS 'mint(address, uint256)' 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 100
echo "Toyken balance of 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266: "
cast call $TOYKEN_ADDRESS --rpc-url http://localhost:8545 "balanceOf(address)(uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# Extract the Counter contract address
export COUNTER_ADDRESS=$(jq -re '.transactions[] | select(.contractName == "Counter") | .contractAddress' ./broadcast/Deploy.s.sol/31337/run-latest.json)
echo "Counter Address: $COUNTER_ADDRESS"

echo "Transfering Toyken to counter"
cast send --private-key $ETH_WALLET_PRIVATE_KEY --rpc-url http://localhost:8545 $TOYKEN_ADDRESS 'approve(address, uint256)' $COUNTER_ADDRESS 100
cast send --private-key $ETH_WALLET_PRIVATE_KEY --rpc-url http://localhost:8545 $COUNTER_ADDRESS 'withdraw(uint256)' 100

echo "withdrawn amount"
cast call $COUNTER_ADDRESS --rpc-url http://localhost:8545 "balanceOf(address)(uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# # Publish a new state
echo "Publishing a new state..."
RUST_LOG=debug cargo run --bin publisher -- \
    --chain-id=31337 \
    --rpc-url=http://localhost:8545 \
    --contract=${COUNTER_ADDRESS:?} \
    --account=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --amount=100

# Attempt to verify counter value as part of the script logic
echo "Verifying state..."
IS_VERIFIED=$(cast call --rpc-url http://localhost:8545 ${COUNTER_ADDRESS:?} 'checkVerified(address)' 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)
if [ "$IS_VERIFIED" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "Counter value verification failed"
    exit 1
fi

echo "All operations completed successfully."
