// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Cfg} from "../script/Config.sol";
import {MinimalUUPS} from "../src/MinimalUUPS.sol";
import {IdentityRegistryUpgradeable} from "../src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "../src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "../src/ValidationRegistryUpgradeable.sol";

/**
 * @dev Shared fixture. Brings the stack up exactly the way `Deploy.s.sol` does
 * -- proxy on the placeholder, then `upgradeToAndCall` into the real
 * implementation -- so the tests exercise the production init path rather than
 * a shortcut that skips the placeholder.
 */
abstract contract Base is Test {
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");

    IdentityRegistryUpgradeable internal identity;
    ReputationRegistryUpgradeable internal reputation;
    ValidationRegistryUpgradeable internal validation;

    MinimalUUPS internal placeholder;
    address internal owner = Cfg.OWNER;

    address internal alice;
    address internal bob;
    address internal carol;
    address internal validator;
    uint256 internal alicePk;
    uint256 internal bobPk;
    uint256 internal carolPk;

    function setUp() public virtual {
        (alice, alicePk) = makeAddrAndKey("alice");
        (bob, bobPk) = makeAddrAndKey("bob");
        (carol, carolPk) = makeAddrAndKey("carol");
        validator = makeAddr("validator");

        placeholder = new MinimalUUPS();
        bytes memory initCalldata = abi.encodeCall(MinimalUUPS.initialize, (owner));

        identity = IdentityRegistryUpgradeable(address(new ERC1967Proxy(address(placeholder), initCalldata)));
        reputation = ReputationRegistryUpgradeable(address(new ERC1967Proxy(address(placeholder), initCalldata)));
        validation = ValidationRegistryUpgradeable(address(new ERC1967Proxy(address(placeholder), initCalldata)));

        vm.startPrank(owner);
        UUPSUpgradeable(address(identity))
            .upgradeToAndCall(
                address(new IdentityRegistryUpgradeable()), abi.encodeCall(IdentityRegistryUpgradeable.initialize, ())
            );
        UUPSUpgradeable(address(reputation))
            .upgradeToAndCall(
                address(new ReputationRegistryUpgradeable()),
                abi.encodeCall(ReputationRegistryUpgradeable.initialize, (address(identity)))
            );
        UUPSUpgradeable(address(validation))
            .upgradeToAndCall(
                address(new ValidationRegistryUpgradeable()),
                abi.encodeCall(ValidationRegistryUpgradeable.initialize, (address(identity)))
            );
        vm.stopPrank();
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    function _register(address who, string memory uri) internal returns (uint256 agentId) {
        vm.prank(who);
        agentId = identity.register(uri);
    }

    function _implOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPL_SLOT))));
    }

    function _signAgentWallet(uint256 pk, uint256 agentId, address newWallet, address agentOwner, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, agentOwner, deadline));
        (, string memory name, string memory version, uint256 chainId, address verifying,,) = identity.eip712Domain();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifying
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));
        return abi.encodePacked(r, s, v);
    }

    function _addrs(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function _addrs(address a, address b) internal pure returns (address[] memory out) {
        out = new address[](2);
        out[0] = a;
        out[1] = b;
    }

    function _noAddrs() internal pure returns (address[] memory out) {
        out = new address[](0);
    }
}
