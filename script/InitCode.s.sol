// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Cfg} from "./Config.sol";

/**
 * @title InitCode
 * @dev Prints the init code hashes `mine.sh` feeds to `cast create2`, and the
 * addresses the current salts resolve to. Machine-readable `KEY=value` lines.
 *
 *   forge script script/InitCode.s.sol
 */
contract InitCode is Script {
    function run() external view {
        console2.log(string.concat("OWNER=", vm.toString(Cfg.OWNER)));
        console2.log(string.concat("CREATE2_FACTORY=", vm.toString(Cfg.CREATE2_FACTORY)));
        console2.log(string.concat("MINIMAL_UUPS_INIT_CODE_HASH=", vm.toString(keccak256(Cfg.minimalUUPSInitCode()))));
        console2.log(string.concat("MINIMAL_UUPS_ADDRESS=", vm.toString(Cfg.minimalUUPSAddress())));
        console2.log(string.concat("PROXY_INIT_CODE_HASH=", vm.toString(keccak256(Cfg.proxyInitCode()))));
        console2.log(string.concat("IDENTITY_PROXY=", vm.toString(Cfg.identityProxyAddress())));
        console2.log(string.concat("REPUTATION_PROXY=", vm.toString(Cfg.reputationProxyAddress())));
        console2.log(string.concat("VALIDATION_PROXY=", vm.toString(Cfg.validationProxyAddress())));
        console2.log(string.concat("IDENTITY_IMPL=", vm.toString(Cfg.identityImplAddress())));
        console2.log(string.concat("REPUTATION_IMPL=", vm.toString(Cfg.reputationImplAddress())));
        console2.log(string.concat("VALIDATION_IMPL=", vm.toString(Cfg.validationImplAddress())));
    }
}
