#!/usr/bin/env bash
# Mines the CREATE2 salts for the 0x8004A / 0x8004B / 0x8004C vanity proxy
# addresses and writes them back into script/Config.sol.
#
# Re-run this after:
#   - changing the OWNER address
#   - changing MinimalUUPS.sol
#   - changing any bytecode-affecting compiler setting in foundry.toml
#   - bumping the OpenZeppelin version
# In short: once PROXY_INIT_CODE_HASH changes, the old salts are dead.
# Changing the registry implementations does not move the proxy addresses --
# that is exactly what the placeholder is for.
set -euo pipefail
cd "$(dirname "$0")/.."

forge build --quiet

INFO=$(forge script script/InitCode.s.sol)
get() { echo "$INFO" | grep -o "$1=0x[0-9a-fA-F]*" | head -1 | cut -d= -f2; }

HASH=$(get PROXY_INIT_CODE_HASH)
FACTORY=$(get CREATE2_FACTORY)
OWNER=$(get OWNER)

echo "owner:              $OWNER"
echo "create2 factory:    $FACTORY"
echo "proxy initcodehash: $HASH"
echo

mine() { # $1=prefix
    cast create2 --starts-with "$1" --init-code-hash "$HASH" --deployer "$FACTORY"
}

for spec in "IDENTITY:8004a" "REPUTATION:8004b" "VALIDATION:8004c"; do
    name="${spec%%:*}"
    prefix="${spec##*:}"

    out=$(mine "$prefix")
    addr=$(echo "$out" | awk '/^Address:/ {print $2}')
    salt=$(echo "$out" | awk '/^Salt:/ {print $2}')

    echo "${name}_PROXY  $addr  salt=$salt"

    perl -pi -e \
        "s/(${name}_PROXY_SALT = )bytes32\(0\)|(${name}_PROXY_SALT = )bytes32\(0x[0-9a-fA-F]*\)/\${1}\${2}bytes32(${salt})/" \
        script/Config.sol
done

echo
echo "Written back to script/Config.sol. Verifying:"
forge script script/InitCode.s.sol 2>/dev/null | grep -E "_PROXY=|_IMPL=|MINIMAL_UUPS_ADDRESS="
