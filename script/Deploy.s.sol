// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Cfg} from "./Config.sol";
import {MinimalUUPS} from "../src/MinimalUUPS.sol";
import {IdentityRegistryUpgradeable} from "../src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "../src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "../src/ValidationRegistryUpgradeable.sol";

/**
 * @title Deploy
 * @dev Deploys the full ERC-8004 stack at deterministic addresses.
 *
 *   1. MinimalUUPS placeholder            (CREATE2, permissionless)
 *   2. three vanity proxies on it          (CREATE2, permissionless)
 *   3. three registry implementations      (CREATE2, permissionless)
 *   4. upgrade each proxy to its real impl (owner only)
 *
 * Every step is idempotent: anything already on-chain is detected and skipped,
 * so a re-run after a half-finished deployment resumes rather than reverts.
 * Steps 1-3 can be run by any funded key; step 4 needs `Cfg.OWNER` and is
 * skipped with a warning otherwise (run `Upgrade.s.sol` later with that key).
 *
 *   forge script script/Deploy.s.sol --rpc-url localhost --broadcast
 */
contract Deploy is Script {
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external {
        require(
            Cfg.CREATE2_FACTORY.code.length > 0, "CREATE2 factory not on this chain - see README (anvil ships with it)"
        );

        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        if (pk != 0) {
            vm.startBroadcast(pk);
        } else {
            vm.startBroadcast();
        }
        (, address sender,) = vm.readCallers();

        console2.log("chain id  ", block.chainid);
        console2.log("sender    ", sender);
        console2.log("owner     ", Cfg.OWNER);
        console2.log("");

        // ── 1. placeholder ───────────────────────────────────────────────────
        address placeholder = Cfg.minimalUUPSAddress();
        if (placeholder.code.length == 0) {
            MinimalUUPS deployed = new MinimalUUPS{salt: Cfg.MINIMAL_UUPS_SALT}();
            require(address(deployed) == placeholder, "placeholder address mismatch");
            console2.log("MinimalUUPS        deployed", placeholder);
        } else {
            console2.log("MinimalUUPS        exists  ", placeholder);
        }

        // ── 2. vanity proxies ────────────────────────────────────────────────
        address identity = _deployProxy(Cfg.IDENTITY_PROXY_SALT, Cfg.identityProxyAddress(), "IdentityRegistry  ");
        address reputation = _deployProxy(Cfg.REPUTATION_PROXY_SALT, Cfg.reputationProxyAddress(), "ReputationRegistry");
        address validation = _deployProxy(Cfg.VALIDATION_PROXY_SALT, Cfg.validationProxyAddress(), "ValidationRegistry");

        // ── 3. implementations ───────────────────────────────────────────────
        address identityImpl = Cfg.identityImplAddress();
        if (identityImpl.code.length == 0) {
            require(
                address(new IdentityRegistryUpgradeable{salt: Cfg.IDENTITY_IMPL_SALT}()) == identityImpl,
                "identity impl address mismatch"
            );
            console2.log("IdentityImpl       deployed", identityImpl);
        } else {
            console2.log("IdentityImpl       exists  ", identityImpl);
        }

        address reputationImpl = Cfg.reputationImplAddress();
        if (reputationImpl.code.length == 0) {
            require(
                address(new ReputationRegistryUpgradeable{salt: Cfg.REPUTATION_IMPL_SALT}()) == reputationImpl,
                "reputation impl address mismatch"
            );
            console2.log("ReputationImpl     deployed", reputationImpl);
        } else {
            console2.log("ReputationImpl     exists  ", reputationImpl);
        }

        address validationImpl = Cfg.validationImplAddress();
        if (validationImpl.code.length == 0) {
            require(
                address(new ValidationRegistryUpgradeable{salt: Cfg.VALIDATION_IMPL_SALT}()) == validationImpl,
                "validation impl address mismatch"
            );
            console2.log("ValidationImpl     deployed", validationImpl);
        } else {
            console2.log("ValidationImpl     exists  ", validationImpl);
        }

        // ── 4. upgrades (owner only) ─────────────────────────────────────────
        console2.log("");
        if (sender == Cfg.OWNER) {
            _upgrade(identity, identityImpl, abi.encodeCall(IdentityRegistryUpgradeable.initialize, ()), "Identity  ");
            _upgrade(
                reputation,
                reputationImpl,
                abi.encodeCall(ReputationRegistryUpgradeable.initialize, (identity)),
                "Reputation"
            );
            _upgrade(
                validation,
                validationImpl,
                abi.encodeCall(ValidationRegistryUpgradeable.initialize, (identity)),
                "Validation"
            );
        } else {
            console2.log("!! sender is not the owner - upgrades skipped");
            console2.log("!! run: forge script script/Upgrade.s.sol --rpc-url <net> --broadcast");
            console2.log("!! with the key for", Cfg.OWNER);
        }

        vm.stopBroadcast();

        _writeDeployment(identity, reputation, validation, identityImpl, reputationImpl, validationImpl, placeholder);
    }

    function _deployProxy(bytes32 salt, address expected, string memory label) internal returns (address) {
        if (expected.code.length > 0) {
            console2.log(string.concat(label, " exists  "), expected);
            return expected;
        }
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(Cfg.minimalUUPSAddress(), Cfg.placeholderInitCalldata());
        require(address(proxy) == expected, "proxy address mismatch - salts stale, re-run script/mine.sh");
        console2.log(string.concat(label, " deployed"), expected);
        return expected;
    }

    function _upgrade(address proxy, address impl, bytes memory initData, string memory label) internal {
        address current = address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
        if (current == impl) {
            console2.log(string.concat(label, " already upgraded"));
            return;
        }
        require(current == Cfg.minimalUUPSAddress(), "proxy points at an unexpected implementation");
        UUPSUpgradeable(proxy).upgradeToAndCall(impl, initData);
        console2.log(string.concat(label, " upgraded ->"), impl);
    }

    function _writeDeployment(
        address identity,
        address reputation,
        address validation,
        address identityImpl,
        address reputationImpl,
        address validationImpl,
        address placeholder
    ) internal {
        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeAddress(key, "owner", Cfg.OWNER);
        vm.serializeAddress(key, "minimalUUPS", placeholder);
        vm.serializeAddress(key, "identityRegistry", identity);
        vm.serializeAddress(key, "reputationRegistry", reputation);
        vm.serializeAddress(key, "validationRegistry", validation);
        vm.serializeAddress(key, "identityImpl", identityImpl);
        vm.serializeAddress(key, "reputationImpl", reputationImpl);
        string memory json = vm.serializeAddress(key, "validationImpl", validationImpl);
        vm.writeJson(json, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
    }
}
