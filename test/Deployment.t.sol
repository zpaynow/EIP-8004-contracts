// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {Cfg} from "../script/Config.sol";
import {MinimalUUPS} from "../src/MinimalUUPS.sol";
import {IdentityRegistryUpgradeable} from "../src/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "../src/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "../src/ValidationRegistryUpgradeable.sol";

/**
 * @dev Covers the deployment invariants the vanity scheme rests on, plus the
 * upgrade authorization and storage-preservation guarantees.
 */
contract DeploymentTest is Test {
    bytes32 internal constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _deployViaFactory(bytes32 salt, bytes memory initCode) internal returns (address addr) {
        (bool ok, bytes memory ret) = Cfg.CREATE2_FACTORY.call(abi.encodePacked(salt, initCode));
        require(ok, "create2 deployment failed");
        addr = address(bytes20(ret));
        require(addr.code.length > 0, "nothing deployed");
    }

    function _prefix(address a) internal pure returns (uint256) {
        return uint160(a) >> 140; // top 5 nibbles
    }

    // ── determinism ──────────────────────────────────────────────────────────

    /// @dev The whole vanity scheme is only safe while the committed salts still
    /// match the committed bytecode. This is the test that catches a stale salt.
    function test_MinedSaltsStillMatchTheBytecode() public {
        address placeholder = _deployViaFactory(Cfg.MINIMAL_UUPS_SALT, Cfg.minimalUUPSInitCode());
        assertEq(placeholder, Cfg.minimalUUPSAddress(), "placeholder salt stale");

        assertEq(
            _deployViaFactory(Cfg.IDENTITY_PROXY_SALT, Cfg.proxyInitCode()),
            Cfg.identityProxyAddress(),
            "identity salt stale - re-run script/mine.sh"
        );
        assertEq(
            _deployViaFactory(Cfg.REPUTATION_PROXY_SALT, Cfg.proxyInitCode()),
            Cfg.reputationProxyAddress(),
            "reputation salt stale - re-run script/mine.sh"
        );
        assertEq(
            _deployViaFactory(Cfg.VALIDATION_PROXY_SALT, Cfg.proxyInitCode()),
            Cfg.validationProxyAddress(),
            "validation salt stale - re-run script/mine.sh"
        );
        assertEq(_deployViaFactory(Cfg.IDENTITY_IMPL_SALT, Cfg.identityImplInitCode()), Cfg.identityImplAddress());
        assertEq(_deployViaFactory(Cfg.REPUTATION_IMPL_SALT, Cfg.reputationImplInitCode()), Cfg.reputationImplAddress());
        assertEq(_deployViaFactory(Cfg.VALIDATION_IMPL_SALT, Cfg.validationImplInitCode()), Cfg.validationImplAddress());
    }

    function test_ProxiesKeepTheirVanityPrefixes() public pure {
        assertEq(_prefix(Cfg.identityProxyAddress()), 0x8004a);
        assertEq(_prefix(Cfg.reputationProxyAddress()), 0x8004b);
        assertEq(_prefix(Cfg.validationProxyAddress()), 0x8004c);
    }

    /// @dev Deterministic addresses are public, so anyone can deploy this init
    /// code on a chain we have not reached yet. That is only safe because the
    /// owner travels inside the init calldata: a stranger's deployment still
    /// hands ownership to us.
    function test_StrangerDeployingTheSameInitCodeStillYieldsOurOwner() public {
        _deployViaFactory(Cfg.MINIMAL_UUPS_SALT, Cfg.minimalUUPSInitCode());

        vm.prank(makeAddr("front-runner"));
        address proxy = _deployViaFactory(Cfg.IDENTITY_PROXY_SALT, Cfg.proxyInitCode());

        assertEq(proxy, Cfg.identityProxyAddress());
        assertEq(MinimalUUPS(proxy).owner(), Cfg.OWNER);
    }

    // ── initialization safety ────────────────────────────────────────────────

    function test_RevertWhen_ImplementationsAreInitializedDirectly() public {
        IdentityRegistryUpgradeable identityImpl = new IdentityRegistryUpgradeable();
        ReputationRegistryUpgradeable reputationImpl = new ReputationRegistryUpgradeable();
        ValidationRegistryUpgradeable validationImpl = new ValidationRegistryUpgradeable();
        MinimalUUPS placeholder = new MinimalUUPS();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        identityImpl.initialize();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        reputationImpl.initialize(address(1));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        validationImpl.initialize(address(1));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        placeholder.initialize(address(1));
    }

    function test_RevertWhen_PlaceholderOwnerIsZero() public {
        MinimalUUPS placeholder = new MinimalUUPS();
        vm.expectRevert(bytes("bad owner"));
        new ERC1967Proxy(address(placeholder), abi.encodeCall(MinimalUUPS.initialize, (address(0))));
    }

    function test_RevertWhen_RegistryInitializedWithZeroIdentity() public {
        (, address reputation,) = _bringUpPlaceholders();
        address impl = address(new ReputationRegistryUpgradeable());

        vm.prank(Cfg.OWNER);
        vm.expectRevert(bytes("bad identity"));
        UUPSUpgradeable(reputation)
            .upgradeToAndCall(impl, abi.encodeCall(ReputationRegistryUpgradeable.initialize, (address(0))));
    }

    function test_RevertWhen_InitializeRunsTwice() public {
        (address identity,,) = _bringUpPlaceholders();
        vm.startPrank(Cfg.OWNER);
        UUPSUpgradeable(identity)
            .upgradeToAndCall(
                address(new IdentityRegistryUpgradeable()), abi.encodeCall(IdentityRegistryUpgradeable.initialize, ())
            );
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        IdentityRegistryUpgradeable(identity).initialize();
        vm.stopPrank();
    }

    // ── upgrade authorization ────────────────────────────────────────────────

    function test_RevertWhen_NonOwnerUpgrades() public {
        (address identity,,) = _bringUpPlaceholders();
        address stranger = makeAddr("stranger");
        address impl = address(new IdentityRegistryUpgradeable());

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, stranger));
        UUPSUpgradeable(identity).upgradeToAndCall(impl, "");
    }

    function test_UpgradeEmitsUpgradedEvent() public {
        (address identity,,) = _bringUpPlaceholders();
        address impl = address(new IdentityRegistryUpgradeable());

        vm.expectEmit(true, false, false, false, identity);
        emit IERC1967.Upgraded(impl);

        vm.prank(Cfg.OWNER);
        UUPSUpgradeable(identity).upgradeToAndCall(impl, abi.encodeCall(IdentityRegistryUpgradeable.initialize, ()));
        assertEq(address(uint160(uint256(vm.load(identity, IMPL_SLOT)))), impl);
    }

    function test_OwnershipTransferMovesUpgradeRights() public {
        (address identity,,) = _bringUpPlaceholders();
        address newOwner = makeAddr("new-owner");
        address impl = address(new IdentityRegistryUpgradeable());

        vm.prank(Cfg.OWNER);
        MinimalUUPS(identity).transferOwnership(newOwner);

        vm.prank(Cfg.OWNER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, Cfg.OWNER));
        UUPSUpgradeable(identity).upgradeToAndCall(impl, "");

        vm.prank(newOwner);
        UUPSUpgradeable(identity).upgradeToAndCall(impl, abi.encodeCall(IdentityRegistryUpgradeable.initialize, ()));
        assertEq(IdentityRegistryUpgradeable(identity).owner(), newOwner);
    }

    // ── storage across upgrades ──────────────────────────────────────────────

    function test_StorageSurvivesAnotherUpgrade() public {
        (address identityAddr, address reputationAddr,) = _bringUpPlaceholders();

        vm.startPrank(Cfg.OWNER);
        UUPSUpgradeable(identityAddr)
            .upgradeToAndCall(
                address(new IdentityRegistryUpgradeable()), abi.encodeCall(IdentityRegistryUpgradeable.initialize, ())
            );
        UUPSUpgradeable(reputationAddr)
            .upgradeToAndCall(
                address(new ReputationRegistryUpgradeable()),
                abi.encodeCall(ReputationRegistryUpgradeable.initialize, (identityAddr))
            );
        vm.stopPrank();

        IdentityRegistryUpgradeable identity = IdentityRegistryUpgradeable(identityAddr);
        ReputationRegistryUpgradeable reputation = ReputationRegistryUpgradeable(reputationAddr);

        address agentOwner = makeAddr("agent-owner");
        address client = makeAddr("client");
        vm.prank(agentOwner);
        uint256 agentId = identity.register("ipfs://before-upgrade");
        vm.prank(agentOwner);
        identity.setMetadata(agentId, "k", bytes("v"));
        vm.prank(client);
        reputation.giveFeedback(agentId, 4200, 2, "speed", "eu", "", "", bytes32(0));

        // move both proxies onto freshly deployed implementations
        vm.startPrank(Cfg.OWNER);
        UUPSUpgradeable(identityAddr).upgradeToAndCall(address(new IdentityRegistryUpgradeable()), "");
        UUPSUpgradeable(reputationAddr).upgradeToAndCall(address(new ReputationRegistryUpgradeable()), "");
        vm.stopPrank();

        assertEq(identity.ownerOf(agentId), agentOwner);
        assertEq(identity.tokenURI(agentId), "ipfs://before-upgrade");
        assertEq(identity.getMetadata(agentId, "k"), bytes("v"));
        assertEq(identity.getAgentWallet(agentId), agentOwner);

        (int128 value, uint8 decimals, string memory tag1,,) = reputation.readFeedback(agentId, client, 1);
        assertEq(value, 4200);
        assertEq(decimals, 2);
        assertEq(tag1, "speed");
        assertEq(reputation.getIdentityRegistry(), identityAddr, "slot 0 must survive the upgrade");
    }

    /// @dev Slot 0 is shared between the placeholder (which leaves it empty) and
    /// the real implementations (which store `_identityRegistry` there).
    function test_SlotZeroIsEmptyUntilTheRealImplementationSetsIt() public {
        (address identity, address reputation,) = _bringUpPlaceholders();
        assertEq(uint256(vm.load(reputation, bytes32(0))), 0, "placeholder must not write slot 0");
        address impl = address(new ReputationRegistryUpgradeable());

        vm.prank(Cfg.OWNER);
        UUPSUpgradeable(reputation)
            .upgradeToAndCall(impl, abi.encodeCall(ReputationRegistryUpgradeable.initialize, (identity)));

        assertEq(address(uint160(uint256(vm.load(reputation, bytes32(0))))), identity);
    }

    function test_PlaceholderReportsItsOwnVersion() public {
        (address identity,,) = _bringUpPlaceholders();
        assertEq(MinimalUUPS(identity).getVersion(), "0.0.1-placeholder");
    }

    function _bringUpPlaceholders() internal returns (address identity, address reputation, address validation) {
        MinimalUUPS placeholder = new MinimalUUPS();
        bytes memory data = abi.encodeCall(MinimalUUPS.initialize, (Cfg.OWNER));
        identity = address(new ERC1967Proxy(address(placeholder), data));
        reputation = address(new ERC1967Proxy(address(placeholder), data));
        validation = address(new ERC1967Proxy(address(placeholder), data));
    }
}
