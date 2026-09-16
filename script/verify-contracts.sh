#!/usr/bin/env bash
# Verify the deployed contracts on a Blockscout explorer.
#
#   ./script/verify-contracts.sh "$EXPLORER_API"
#
# Why this is not just `forge verify-contract`: some Blockscout deployments sit
# behind a WAF that 403s any verification payload much over ~100KB, and every
# one of our standard-json inputs is ~210KB with the OpenZeppelin sources
# included. So we generate the same standard-json foundry would send, strip the
# comments from it -- which cannot change the bytecode, see
# script/minify-standard-json.py -- and post it ourselves.
#
# Kept separate from deployment on purpose: a flaky explorer should never be
# able to fail a deployment that already landed on-chain.
set -uo pipefail          # deliberately not -e: one contract failing must not
                          # abort the rest of the batch
cd "$(dirname "$0")/.."

# foundry resolves the whole [etherscan] table before it will print a
# standard-json input, and errors out on an unset ${ETHERSCAN_API_KEY} even
# though nothing here talks to Etherscan. Give it an empty one.
export ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:-}"

API=${1:?usage: verify-contracts.sh <blockscout-api-url>}
COMPILER=v0.8.24+commit.e11b9ed9
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

INFO=$(forge script script/InitCode.s.sol)
get() { echo "$INFO" | grep -o "$1=0x[0-9a-fA-F]*" | head -1 | cut -d= -f2; }

PLACEHOLDER=$(get MINIMAL_UUPS_ADDRESS)
PROXY_ARGS=$(cast abi-encode "constructor(address,bytes)" "$PLACEHOLDER" "$(get PLACEHOLDER_INIT_CALLDATA)")

verify() { # $1=address $2=file:Name $3=optional constructor args (0x-prefixed)
    local addr=$1 target=$2 ctor=${3:-}
    printf '── %-28s %s\n' "${target##*:}" "$addr"

    if ! forge verify-contract --show-standard-json-input "$addr" "$target" > "$WORK/in.json" 2>"$WORK/err"; then
        echo "   could not build standard-json: $(head -c 200 "$WORK/err")"
        return
    fi
    python3 script/minify-standard-json.py "$WORK/in.json" "$WORK/min.json" || { echo "   minify failed"; return; }
    local size=$(wc -c < "$WORK/min.json")
    if [ "$size" -gt 102400 ]; then
        echo "   payload is ${size}B, over the ~100KB a WAF typically accepts - verify this one by hand"
        return
    fi

    local args=(--data-urlencode "contractaddress=$addr"
                --data-urlencode "sourceCode@$WORK/min.json"
                --data-urlencode "codeformat=solidity-standard-json-input"
                --data-urlencode "contractname=$target"
                --data-urlencode "compilerversion=$COMPILER"
                --data-urlencode "optimizationUsed=1"
                --data-urlencode "runs=200")
    [ -n "$ctor" ] && args+=(--data-urlencode "constructorArguements=${ctor#0x}")

    local resp guid
    resp=$(curl -s -m 180 -X POST "$API?module=contract&action=verifysourcecode" "${args[@]}")
    if echo "$resp" | grep -qiE "cloudflare|<!DOCTYPE"; then echo "   blocked by the WAF (${size}B payload)"; return; fi

    guid=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || true)
    if [ -z "$guid" ] || echo "$resp" | grep -q '"status":"0"'; then
        echo "   $(echo "$resp" | head -c 200)"
        return
    fi

    for _ in $(seq 1 20); do
        sleep 6
        local st
        st=$(curl -s -m 60 "$API?module=contract&action=checkverifystatus&guid=$guid" \
             | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || true)
        case "$st" in
            "Pass - Verified") echo "   verified"; return ;;
            "Pending in queue") ;;
            *) echo "   $st"; return ;;
        esac
    done
    echo "   still pending, check the explorer"
}

verify "$PLACEHOLDER"           src/MinimalUUPS.sol:MinimalUUPS
verify "$(get IDENTITY_IMPL)"   src/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable
verify "$(get REPUTATION_IMPL)" src/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable
verify "$(get VALIDATION_IMPL)" src/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable

PROXY=lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy
verify "$(get IDENTITY_PROXY)"   "$PROXY" "$PROXY_ARGS"
verify "$(get REPUTATION_PROXY)" "$PROXY" "$PROXY_ARGS"
verify "$(get VALIDATION_PROXY)" "$PROXY" "$PROXY_ARGS"
