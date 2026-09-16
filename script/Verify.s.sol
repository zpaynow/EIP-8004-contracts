// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Cfg} from "./Config.sol";
import {IdentityRegistryUpgradeable} from "../src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "../src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "../src/ValidationRegistryUpgradeable.sol";

/**
 * @title Verify
 * @dev Read-only post-deployment check. Reverts on the first thing that is
 * wrong, so it doubles as a smoke test in CI against a live chain.
 *
 *   forge script script/Verify.s.sol --rpc-url <net>
 */
contract Verify is Script {
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external view {
        address identity = Cfg.identityProxyAddress();
        address reputation = Cfg.reputationProxyAddress();
        address validation = Cfg.validationProxyAddress();

        console2.log("chain id", block.chainid);
        console2.log("");

        _checkProxy(identity, Cfg.identityImplAddress(), "IdentityRegistry  ");
        _checkProxy(reputation, Cfg.reputationImplAddress(), "ReputationRegistry");
        _checkProxy(validation, Cfg.validationImplAddress(), "ValidationRegistry");

        // Ownership
        require(IdentityRegistryUpgradeable(identity).owner() == Cfg.OWNER, "identity owner wrong");
        require(ReputationRegistryUpgradeable(reputation).owner() == Cfg.OWNER, "reputation owner wrong");
        require(ValidationRegistryUpgradeable(validation).owner() == Cfg.OWNER, "validation owner wrong");
        console2.log("owner              ok  ", Cfg.OWNER);

        // Cross-registry wiring: these are set by `initialize` during the
        // upgrade, so a zero here means the proxy was never upgraded.
        require(ReputationRegistryUpgradeable(reputation).getIdentityRegistry() == identity, "reputation -> identity");
        require(ValidationRegistryUpgradeable(validation).getIdentityRegistry() == identity, "validation -> identity");
        console2.log("cross-registry     ok");

        // ERC-721 init ran
        require(
            keccak256(bytes(IdentityRegistryUpgradeable(identity).name())) == keccak256("AgentIdentity"),
            "identity ERC721 not initialized"
        );
        console2.log("erc721 metadata    ok  ", IdentityRegistryUpgradeable(identity).name());

        console2.log("");
        console2.log("versions");
        console2.log("  identity  ", IdentityRegistryUpgradeable(identity).getVersion());
        console2.log("  reputation", ReputationRegistryUpgradeable(reputation).getVersion());
        console2.log("  validation", ValidationRegistryUpgradeable(validation).getVersion());
        console2.log("");
        console2.log("all checks passed");
    }

    function _checkProxy(address proxy, address expectedImpl, string memory label) internal view {
        require(proxy.code.length > 0, string.concat(label, ": no code at proxy"));
        address impl = address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
        require(impl != Cfg.minimalUUPSAddress(), string.concat(label, ": still on the placeholder, not upgraded"));
        require(impl == expectedImpl, string.concat(label, ": implementation is not the one this build produces"));
        console2.log(string.concat(label, " ok  "), proxy);
    }
}
