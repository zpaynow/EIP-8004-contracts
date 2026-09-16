.PHONY: build test fmt mine anvil local deploy upgrade verify clean

build:      ; forge build
test:       ; forge test
fmt:        ; forge fmt script test
clean:      ; forge clean

# Mine the vanity salts and write them back into script/Config.sol.
# Only needed after changing the owner or MinimalUUPS.
mine:       ; ./script/mine.sh

anvil:      ; anvil --auto-impersonate
local:      ; ./script/local.sh

# On-chain: make deploy NET=base_sepolia
deploy:     ; forge script script/Deploy.s.sol  --rpc-url $(NET) --broadcast --verify
upgrade:    ; forge script script/Upgrade.s.sol --rpc-url $(NET) --broadcast --verify
verify:     ; forge script script/Verify.s.sol  --rpc-url $(NET)
