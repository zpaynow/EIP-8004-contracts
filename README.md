# ERC-8004 Registries (zpaynow)

A self-hosted deployment of the [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004)
trustless-agent registries. The registry contracts are taken verbatim from the upstream
[erc-8004/erc-8004-contracts](https://github.com/erc-8004/erc-8004-contracts) repository;
this repo swaps the toolchain for Foundry and deploys them under our own owner key and our
own CREATE2 salts.

> **This is not the canonical ERC-8004 deployment.** The addresses below share the
> `0x8004A/B/C` prefix style with the official registries but are a *separate* set of
> contracts, controlled by zpaynow. If you are looking for the community deployment that
> the ERC-8004 ecosystem indexes, use the addresses published by
> [erc-8004/erc-8004-contracts](https://github.com/erc-8004/erc-8004-contracts) instead.

## Addresses

The three proxies are deployed with CREATE2, so they carry **the same address on every chain**:

| Contract | Address |
|---|---|
| IdentityRegistry | `0x8004A3299823a3A0a7E4F1625A2760e5b9053Caa` |
| ReputationRegistry | `0x8004BD8c82D8958d3Bc7607beb6Bc6AE462E91d2` |
| ValidationRegistry | `0x8004C49DFb3D283a15a35B0E62Da62CB3756a3Fb` |
| MinimalUUPS (placeholder implementation) | `0x23B7C30F1cF35FBc4693D237aF130d78a27d775d` |
| Owner (upgrade authority) | `0xbB64D716FAbDEC3a106bb913Fb4f82c1EeC851b8` |

### Live deployments

Every chain the registries have been deployed to has a record in
`deployments/<chainId>.json`, listing the proxies, the implementations behind them and the
owner. Sources are published to the chain's explorer as part of each deployment.

### Agent identifiers

ERC-8004 identifies an agent by `{namespace}:{chainId}:{identityRegistry}` plus the `agentId`
minted by the Identity Registry:

```
eip155:<chainId>:0x8004A3299823a3A0a7E4F1625A2760e5b9053Caa
```

Because CREATE2 gives the registry the same address on every chain, **the chain id is the
only thing separating one deployment from another** -- mainnet and testnet included. Do not
let the two blur together in SDKs or documentation.

That string belongs in the `registrations` field of the agent's registration file, the JSON
that `agentURI` resolves to, binding the off-chain description to the on-chain identity.

### Which contract to integrate against

The **IdentityRegistry** is the root of the system: identities are minted there, and the
other two registries call into it to authorize writes. Integrators who only need agent
discovery need nothing else. Reputation and Validation are optional trust layers on top.

| You are | You call |
|---|---|
| an agent that wants to be discoverable | `IdentityRegistry.register(agentURI)` |
| a client leaving feedback | `ReputationRegistry.giveFeedback(...)` |
| a validator | `ValidationRegistry.validationRequest` / `validationResponse` |

## Quickstart

```bash
forge build
forge test          # 83 tests

# full local run
anvil --auto-impersonate     # in a second terminal
make local                   # deploy + verify
```

## Deploying to a new chain

```bash
cp .env.example .env         # set PRIVATE_KEY (the owner key) and the RPC URL
make deploy NET=base_sepolia
make verify NET=base_sepolia
```

Point `TARGET_RPC_URL` / `TARGET_TESTNET_RPC_URL` and `EXPLORER_API` /
`EXPLORER_TESTNET_API` at the chain in `.env`, then:

```bash
make dry-test       # simulate against the live chain, spends nothing
make deploy-test
make check-test     # on-chain assertions: owner, implementations, cross-registry wiring
make src-test       # publish sources to the explorer

make dry / deploy / check / src      # same, against TARGET_RPC_URL
```

`Deploy.s.sol` runs all four steps and is **idempotent** — if it fails halfway, just run it
again and anything already on-chain is detected and skipped:

1. Deploy the `MinimalUUPS` placeholder (CREATE2, permissionless)
2. Deploy the three vanity proxies on top of it (CREATE2, permissionless)
3. Deploy the three registry implementations (CREATE2, permissionless)
4. `upgradeToAndCall` each proxy to its real implementation (**owner only**)

Steps 1–3 need no privileges, so a throwaway hot wallet can do the deployment and the owner
can finish step 4 later with `make upgrade NET=<net>`. When `Deploy.s.sol` sees that the
signer is not the owner, it skips step 4 and says so instead of reverting.

Prerequisite: the target chain needs the CREATE2 factory at
`0x4e59b44847b379578588920cA78FbF26c0B4956C`. Almost every EVM chain has it and anvil ships
with it; if a chain does not, it can be deployed with the usual Nick's-method presigned
transaction.

### Source verification behind a WAF

`make src` / `make src-test` do not shell out to `forge verify-contract`. Blockscout
instances are often fronted by a WAF that 403s verification payloads over roughly 100KB, and
our standard-json inputs are ~210KB once the OpenZeppelin sources are included.

`script/verify-contracts.sh` generates the same standard-json foundry would send, strips the
comments out of it, and posts it directly. Stripping comments cannot change the bytecode --
`bytecode_hash = "none"` and `cbor_metadata = false` keep metadata out of the compiled output
entirely -- and it halves the payload to ~97KB, under the limit. Verification is deliberately
a separate step from deployment so that a flaky explorer can never fail a deployment that has
already landed on-chain.

## Why there is a placeholder implementation

A proxy's CREATE2 address depends on its constructor arguments, i.e. on the implementation
address and the init calldata. If the proxies pointed straight at the real implementations,
every change to a registry would move the proxy address and burn the mined `0x8004` vanity
addresses.

Pinning the proxies to a tiny, frozen `MinimalUUPS` decouples the proxy addresses from the
registry bytecode, so the implementations can keep evolving while the addresses stay put.

The two-step dance is also mandatory rather than stylistic: all three implementations declare
`initialize` as `reinitializer(2) onlyOwner`, which requires an owner to already exist by the
time it runs. Deploying a proxy directly onto a real implementation would revert.

## Security: why the owner lives in the init calldata

Deterministic addresses are public, so anyone can deploy this init code on a chain we have
not reached yet and land on the same address before we do.

That is harmless here because the owner is encoded into the proxy's init calldata, and
therefore baked into the address itself: reproducing the init code reproduces *our*
ownership. Had `MinimalUUPS` derived its owner from `msg.sender` or `tx.origin` instead, a
front-runner would walk away with the upgrade rights on that chain.

`test_StrangerDeployingTheSameInitCodeStillYieldsOurOwner` pins this property down.

## When the salts need re-mining

```bash
make mine        # re-mines and writes the result back into script/Config.sol
```

Any change to `PROXY_INIT_CODE_HASH` invalidates the committed salts:

- changing `OWNER`
- changing `src/MinimalUUPS.sol`
- changing any bytecode-affecting compiler setting in `foundry.toml`
- bumping the OpenZeppelin version

Changing the three registry implementations does **not** require re-mining — that is exactly
what the placeholder buys.

`test_MinedSaltsStillMatchTheBytecode` fails outright when a salt no longer matches the
bytecode it was mined against, so a stale configuration cannot go unnoticed.

## The compiler settings are frozen

The solc version, EVM version, optimizer settings and `via_ir` flag in `foundry.toml` all
feed into the bytecode, and therefore into every CREATE2 address. `bytecode_hash = "none"`
and `cbor_metadata = false` strip the trailing metadata so that addresses stay reproducible
across comment edits, directory moves and machines.

## Layout

```
src/                          the three registry implementations + the MinimalUUPS placeholder
script/
  Config.sol                  owner / salts / init code / address derivation (single source of truth)
  Deploy.s.sol                full deployment, idempotent
  Upgrade.s.sol               owner-only upgrade, also used for later implementation revisions
  Verify.s.sol                read-only post-deployment checks, usable as a CI smoke test
  InitCode.s.sol              prints init code hashes and derived addresses
  mine.sh / local.sh
  verify-contracts.sh         publishes sources to Blockscout
  minify-standard-json.py     shrinks the verification payload past the WAF limit
test/                         83 tests
deployments/<chainId>.json    per-chain deployment records
```

## Differences from upstream

| | Upstream (hardhat) | This repo (foundry) |
|---|---|---|
| Owner | `0x547289…` (held by the ERC-8004 team) | `0xbB64D7…` (held by us) |
| How the owner is set | hardcoded in MinimalUUPS | an `initialize` parameter, so changing it needs no recompile |
| Upgrade transactions | presigned JSON files, which drift out of sync with the bytecode | signed by the owner directly, no intermediate artifact |
| CREATE2 factory | SAFE Singleton `0x914d7F…` | generic deterministic proxy `0x4e59b4…` (built into anvil) |
| Salt mining | a bespoke multi-process TypeScript miner | `cast create2`, ~75ms |
| Tests | TypeScript / viem, 79 | Solidity, 83 |

## License and attribution

This repository is released under the [MIT License](LICENSE), matching the SPDX headers
carried by every Solidity file in it.

The registry contracts in `src/` are copied from
[erc-8004/erc-8004-contracts](https://github.com/erc-8004/erc-8004-contracts), which is
published under CC0-1.0 and ships those files with MIT SPDX headers. The deployment tooling
in `script/` and the test suite in `test/` are original to this repo.

ERC-8004 itself is a community effort coordinated by Marco De Rossi (MetaMask) and Davide
Crapis (EF); see [8004.org](https://www.8004.org) and the
[specification](https://eips.ethereum.org/EIPS/eip-8004).
