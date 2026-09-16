// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MinimalUUPS} from "../src/MinimalUUPS.sol";
import {IdentityRegistryUpgradeable} from "../src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "../src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "../src/ValidationRegistryUpgradeable.sol";

/**
 * @title Cfg
 * @dev Single source of truth for every address the deployment depends on.
 *
 * Mining, deploying, verifying and testing all derive their addresses from the
 * functions below, so a salt can never drift out of sync with the bytecode it
 * was mined against: if the init code changes, every consumer moves with it and
 * `Deploy` fails its address assertion instead of silently deploying elsewhere.
 */
library Cfg {
    /// @dev Upgrade authority for all three registries. Baked into the proxy
    /// init calldata, so re-deploying this init code on a new chain always
    /// reproduces this owner. Changing it invalidates the mined salts below.
    address internal constant OWNER = 0xbB64D716FAbDEC3a106bb913Fb4f82c1EeC851b8;

    /// @dev Deterministic deployment proxy (Nick's method). Built into anvil and
    /// present on essentially every EVM chain; `new C{salt: s}()` routes through it.
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // ── Salts ────────────────────────────────────────────────────────────────
    // Proxy salts are mined for the 0x8004A/B/C prefixes by `script/mine.sh`.
    // The placeholder and implementation salts are arbitrary but fixed, so the
    // addresses stay identical across chains.

    bytes32 internal constant MINIMAL_UUPS_SALT = bytes32(uint256(0x01));

    bytes32 internal constant IDENTITY_PROXY_SALT =
        bytes32(0x3194b13a72a2922c2d5f6bad8a438b4e1825d8e2050441bb2f46cd4d2c367ef4);
    bytes32 internal constant REPUTATION_PROXY_SALT =
        bytes32(0xecabf0cdc0e98fbd184c2a2553e0cfefafef93b0c552a2683af7d14c6ca6d0bb);
    bytes32 internal constant VALIDATION_PROXY_SALT =
        bytes32(0xa56504b7a5fe8156daaf2883399ff69305e817bae1387f32b953f452fc993c1d);

    bytes32 internal constant IDENTITY_IMPL_SALT = bytes32(uint256(0x11));
    bytes32 internal constant REPUTATION_IMPL_SALT = bytes32(uint256(0x12));
    bytes32 internal constant VALIDATION_IMPL_SALT = bytes32(uint256(0x13));

    // ── Init code ────────────────────────────────────────────────────────────

    function minimalUUPSInitCode() internal pure returns (bytes memory) {
        return type(MinimalUUPS).creationCode;
    }

    /// @dev Calldata the proxies are constructed with. Identical for all three:
    /// the placeholder only sets the owner, and `_identityRegistry` (slot 0) is
    /// written later by the real implementation's `initialize`. Keeping it
    /// identical means the three proxies share one init code and can be mined
    /// independently, with no ordering dependency between them.
    function placeholderInitCalldata() internal pure returns (bytes memory) {
        return abi.encodeCall(MinimalUUPS.initialize, (OWNER));
    }

    function proxyInitCode() internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(ERC1967Proxy).creationCode, abi.encode(minimalUUPSAddress(), placeholderInitCalldata())
            );
    }

    function identityImplInitCode() internal pure returns (bytes memory) {
        return type(IdentityRegistryUpgradeable).creationCode;
    }

    function reputationImplInitCode() internal pure returns (bytes memory) {
        return type(ReputationRegistryUpgradeable).creationCode;
    }

    function validationImplInitCode() internal pure returns (bytes memory) {
        return type(ValidationRegistryUpgradeable).creationCode;
    }

    // ── Derived addresses ────────────────────────────────────────────────────

    function minimalUUPSAddress() internal pure returns (address) {
        return create2Address(MINIMAL_UUPS_SALT, keccak256(minimalUUPSInitCode()));
    }

    function identityProxyAddress() internal pure returns (address) {
        return create2Address(IDENTITY_PROXY_SALT, keccak256(proxyInitCode()));
    }

    function reputationProxyAddress() internal pure returns (address) {
        return create2Address(REPUTATION_PROXY_SALT, keccak256(proxyInitCode()));
    }

    function validationProxyAddress() internal pure returns (address) {
        return create2Address(VALIDATION_PROXY_SALT, keccak256(proxyInitCode()));
    }

    function identityImplAddress() internal pure returns (address) {
        return create2Address(IDENTITY_IMPL_SALT, keccak256(identityImplInitCode()));
    }

    function reputationImplAddress() internal pure returns (address) {
        return create2Address(REPUTATION_IMPL_SALT, keccak256(reputationImplInitCode()));
    }

    function validationImplAddress() internal pure returns (address) {
        return create2Address(VALIDATION_IMPL_SALT, keccak256(validationImplInitCode()));
    }

    function create2Address(bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, salt, initCodeHash)))));
    }
}
