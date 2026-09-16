#!/usr/bin/env bash
# Full local run: anvil -> fund the owner -> deploy -> verify.
# anvil ships with the CREATE2 factory, so unlike upstream there is no separate
# factory deployment step.
set -euo pipefail
cd "$(dirname "$0")/.."

RPC=${RPC:-http://127.0.0.1:8545}
OWNER=$(forge script script/InitCode.s.sol | grep -o 'OWNER=0x[0-9a-fA-F]*' | cut -d= -f2)

if ! cast chain-id --rpc-url "$RPC" >/dev/null 2>&1; then
    echo "No local node reachable. Start one first: anvil --auto-impersonate"
    exit 1
fi

# We do not hold the owner key locally, so impersonate it via anvil and fund it for gas
cast rpc anvil_setBalance "$OWNER" 0x56BC75E2D63100000 --rpc-url "$RPC" >/dev/null

forge script script/Deploy.s.sol --rpc-url "$RPC" --broadcast --unlocked --sender "$OWNER"
echo
forge script script/Verify.s.sol --rpc-url "$RPC"
