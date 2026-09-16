.PHONY: build test fmt mine anvil local clean \
	dry deploy upgrade check src \
	dry-test deploy-test upgrade-test check-test src-test

# Deployment targets and explorer endpoints come from .env, which is never
# committed -- see .env.example for the variables involved.
-include .env
export

build:      ; forge build
test:       ; forge test
fmt:        ; forge fmt script test
clean:      ; forge clean

# Mine the vanity salts and write them back into script/Config.sol.
# Only needed after changing the owner or MinimalUUPS.
mine:       ; ./script/mine.sh

anvil:      ; anvil --auto-impersonate
local:      ; ./script/local.sh

# ── testnet ────────────────────────────────────────────────────────────────
dry-test:     ; forge script script/Deploy.s.sol  --rpc-url target_test
deploy-test:  ; forge script script/Deploy.s.sol  --rpc-url target_test --broadcast
upgrade-test: ; forge script script/Upgrade.s.sol --rpc-url target_test --broadcast
check-test:   ; forge script script/Verify.s.sol  --rpc-url target_test
src-test:     ; ./script/verify-contracts.sh "$(EXPLORER_TESTNET_API)"

# ── mainnet ────────────────────────────────────────────────────────────────
dry:          ; forge script script/Deploy.s.sol  --rpc-url target
deploy:       ; forge script script/Deploy.s.sol  --rpc-url target --broadcast
upgrade:      ; forge script script/Upgrade.s.sol --rpc-url target --broadcast
check:        ; forge script script/Verify.s.sol  --rpc-url target
src:          ; ./script/verify-contracts.sh "$(EXPLORER_API)"
