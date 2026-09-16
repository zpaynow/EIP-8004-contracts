// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Cfg} from "./Config.sol";
import {IdentityRegistryUpgradeable} from "../src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "../src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "../src/ValidationRegistryUpgradeable.sol";

/**
 * @title Upgrade
 * @dev Owner-only step 4 of the deployment, split out so the proxies can be
 * deployed by a throwaway key and the upgrade signed by the owner key later.
 *
 * Also the script to re-run after changing a registry implementation: it
 * redeploys whatever implementation is missing and points the proxy at it.
 * Coming from the placeholder it passes `initialize` calldata (the real impls
 * are `reinitializer(2)`); a later impl-to-impl move passes none, so bump the
 * reinitializer version in the contract if a future version needs init logic.
 *
 *   forge script script/Upgrade.s.sol --rpc-url <net> --broadcast
 */
contract Upgrade is Script {
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        if (pk != 0) {
            vm.startBroadcast(pk);
        } else {
            vm.startBroadcast();
        }
        (, address sender,) = vm.readCallers();
        require(sender == Cfg.OWNER, "sender is not the owner - upgrades would revert");

        address identity = Cfg.identityProxyAddress();

        _step(
            identity,
            Cfg.identityImplAddress(),
            Cfg.identityImplInitCode(),
            Cfg.IDENTITY_IMPL_SALT,
            abi.encodeCall(IdentityRegistryUpgradeable.initialize, ()),
            "Identity  "
        );
        _step(
            Cfg.reputationProxyAddress(),
            Cfg.reputationImplAddress(),
            Cfg.reputationImplInitCode(),
            Cfg.REPUTATION_IMPL_SALT,
            abi.encodeCall(ReputationRegistryUpgradeable.initialize, (identity)),
            "Reputation"
        );
        _step(
            Cfg.validationProxyAddress(),
            Cfg.validationImplAddress(),
            Cfg.validationImplInitCode(),
            Cfg.VALIDATION_IMPL_SALT,
            abi.encodeCall(ValidationRegistryUpgradeable.initialize, (identity)),
            "Validation"
        );

        vm.stopBroadcast();
    }

    function _step(
        address proxy,
        address impl,
        bytes memory implInitCode,
        bytes32 implSalt,
        bytes memory initData,
        string memory label
    ) internal {
        require(proxy.code.length > 0, "proxy not deployed - run Deploy.s.sol first");

        if (impl.code.length == 0) {
            (bool ok,) = Cfg.CREATE2_FACTORY.call(abi.encodePacked(implSalt, implInitCode));
            require(ok && impl.code.length > 0, "implementation deployment failed");
            console2.log(string.concat(label, " impl deployed"), impl);
        }

        address current = address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
        if (current == impl) {
            console2.log(string.concat(label, " already at target impl"));
            return;
        }

        // Only the placeholder needs the `initialize` payload; the real impls
        // have already run their reinitializer by the time we move off them.
        bytes memory data = current == Cfg.minimalUUPSAddress() ? initData : bytes("");
        UUPSUpgradeable(proxy).upgradeToAndCall(impl, data);
        console2.log(string.concat(label, " upgraded ->"), impl);
    }
}
