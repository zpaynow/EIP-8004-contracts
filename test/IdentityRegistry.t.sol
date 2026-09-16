// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.t.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IdentityRegistryUpgradeable} from "../src/IdentityRegistryUpgradeable.sol";

contract IdentityRegistryTest is Base {
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(
        uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue
    );

    function test_RegisterWithURI() public {
        vm.expectEmit(true, true, false, true, address(identity));
        emit Registered(0, "ipfs://agent-0", alice);

        uint256 agentId = _register(alice, "ipfs://agent-0");

        assertEq(agentId, 0);
        assertEq(identity.ownerOf(agentId), alice);
        assertEq(identity.tokenURI(agentId), "ipfs://agent-0");
        assertEq(identity.balanceOf(alice), 1);
    }

    function test_AgentIdAutoIncrements() public {
        assertEq(_register(alice, "a"), 0);
        assertEq(_register(bob, "b"), 1);
        assertEq(_register(alice, "c"), 2);
        assertEq(identity.balanceOf(alice), 2);
    }

    function test_RegisterWithoutURIThenSetIt() public {
        vm.prank(alice);
        uint256 agentId = identity.register();
        assertEq(identity.tokenURI(agentId), "");

        vm.prank(alice);
        identity.setAgentURI(agentId, "https://agent.example/card.json");
        assertEq(identity.tokenURI(agentId), "https://agent.example/card.json");
    }

    function test_OwnerCanUpdateURI() public {
        uint256 agentId = _register(alice, "ipfs://old");

        vm.expectEmit(true, true, false, true, address(identity));
        emit URIUpdated(agentId, "ipfs://new", alice);

        vm.prank(alice);
        identity.setAgentURI(agentId, "ipfs://new");
        assertEq(identity.tokenURI(agentId), "ipfs://new");
    }

    function test_ApprovedOperatorCanUpdateURI() public {
        uint256 agentId = _register(alice, "ipfs://old");
        vm.prank(alice);
        identity.approve(bob, agentId);

        vm.prank(bob);
        identity.setAgentURI(agentId, "ipfs://from-operator");
        assertEq(identity.tokenURI(agentId), "ipfs://from-operator");
    }

    function test_RevertWhen_StrangerUpdatesURI() public {
        uint256 agentId = _register(alice, "ipfs://old");
        vm.prank(bob);
        vm.expectRevert(bytes("Not authorized"));
        identity.setAgentURI(agentId, "ipfs://hijacked");
    }

    function test_SupportsDifferentURISchemes() public {
        string[3] memory uris = [
            "ipfs://QmXyz",
            "https://agent.example/.well-known/agent-card.json",
            "data:application/json;base64,eyJuYW1lIjoiYSJ9"
        ];
        for (uint256 i; i < uris.length; i++) {
            uint256 agentId = _register(alice, uris[i]);
            assertEq(identity.tokenURI(agentId), uris[i]);
        }
    }

    function test_SetAndGetMetadata() public {
        uint256 agentId = _register(alice, "ipfs://a");

        vm.prank(alice);
        identity.setMetadata(agentId, "endpoint", bytes("https://agent.example"));

        assertEq(identity.getMetadata(agentId, "endpoint"), bytes("https://agent.example"));
    }

    function test_RevertWhen_UnauthorizedSetsMetadata() public {
        uint256 agentId = _register(alice, "ipfs://a");
        vm.prank(bob);
        vm.expectRevert(bytes("Not authorized"));
        identity.setMetadata(agentId, "endpoint", bytes("x"));
    }

    function test_RegisterWithMetadataArray() public {
        IdentityRegistryUpgradeable.MetadataEntry[] memory entries = new IdentityRegistryUpgradeable.MetadataEntry[](2);
        entries[0] = IdentityRegistryUpgradeable.MetadataEntry("a2a", bytes("https://a2a.example"));
        entries[1] = IdentityRegistryUpgradeable.MetadataEntry("mcp", bytes("https://mcp.example"));

        vm.prank(alice);
        uint256 agentId = identity.register("ipfs://a", entries);

        assertEq(identity.getMetadata(agentId, "a2a"), bytes("https://a2a.example"));
        assertEq(identity.getMetadata(agentId, "mcp"), bytes("https://mcp.example"));
    }

    function test_RevertWhen_ReservedKeySetViaSetMetadata() public {
        uint256 agentId = _register(alice, "ipfs://a");
        vm.prank(alice);
        vm.expectRevert(bytes("reserved key"));
        identity.setMetadata(agentId, "agentWallet", abi.encodePacked(bob));
    }

    function test_RevertWhen_ReservedKeySetViaRegister() public {
        IdentityRegistryUpgradeable.MetadataEntry[] memory entries = new IdentityRegistryUpgradeable.MetadataEntry[](1);
        entries[0] = IdentityRegistryUpgradeable.MetadataEntry("agentWallet", abi.encodePacked(bob));

        vm.prank(alice);
        vm.expectRevert(bytes("reserved key"));
        identity.register("ipfs://a", entries);
    }

    // ── agentWallet ──────────────────────────────────────────────────────────

    function test_AgentWalletDefaultsToOwnerOnEveryRegisterOverload() public {
        vm.prank(alice);
        uint256 a = identity.register();
        assertEq(identity.getAgentWallet(a), alice);

        uint256 b = _register(alice, "ipfs://b");
        assertEq(identity.getAgentWallet(b), alice);

        IdentityRegistryUpgradeable.MetadataEntry[] memory entries = new IdentityRegistryUpgradeable.MetadataEntry[](1);
        entries[0] = IdentityRegistryUpgradeable.MetadataEntry("k", bytes("v"));
        vm.prank(alice);
        uint256 c = identity.register("ipfs://c", entries);
        assertEq(identity.getAgentWallet(c), alice);
    }

    function test_GetAgentWalletIsZeroForUnknownAgent() public view {
        assertEq(identity.getAgentWallet(999), address(0));
    }

    function test_SetAgentWalletWithEOASignature() public {
        uint256 agentId = _register(alice, "ipfs://a");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signAgentWallet(bobPk, agentId, bob, alice, deadline);

        vm.prank(alice);
        identity.setAgentWallet(agentId, bob, deadline, sig);

        assertEq(identity.getAgentWallet(agentId), bob);
    }

    function test_RevertWhen_AgentWalletSignatureIsFromWrongKey() public {
        uint256 agentId = _register(alice, "ipfs://a");
        uint256 deadline = block.timestamp + 60;
        // carol signs, but the wallet being claimed is bob's
        bytes memory sig = _signAgentWallet(carolPk, agentId, bob, alice, deadline);

        vm.prank(alice);
        vm.expectRevert(bytes("invalid wallet sig"));
        identity.setAgentWallet(agentId, bob, deadline, sig);
    }

    function test_RevertWhen_AgentWalletDeadlineExpired() public {
        uint256 agentId = _register(alice, "ipfs://a");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signAgentWallet(bobPk, agentId, bob, alice, deadline);

        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert(bytes("expired"));
        identity.setAgentWallet(agentId, bob, deadline, sig);
    }

    function test_RevertWhen_AgentWalletDeadlineTooFarOut() public {
        uint256 agentId = _register(alice, "ipfs://a");
        uint256 deadline = block.timestamp + 6 minutes; // MAX_DEADLINE_DELAY is 5 minutes
        bytes memory sig = _signAgentWallet(bobPk, agentId, bob, alice, deadline);

        vm.prank(alice);
        vm.expectRevert(bytes("deadline too far"));
        identity.setAgentWallet(agentId, bob, deadline, sig);
    }

    function test_RevertWhen_AgentWalletSetByStranger() public {
        uint256 agentId = _register(alice, "ipfs://a");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signAgentWallet(bobPk, agentId, bob, alice, deadline);

        vm.prank(carol);
        vm.expectRevert(bytes("Not authorized"));
        identity.setAgentWallet(agentId, bob, deadline, sig);
    }

    function test_RevertWhen_AgentWalletIsZero() public {
        uint256 agentId = _register(alice, "ipfs://a");
        uint256 deadline = block.timestamp + 60;
        vm.prank(alice);
        vm.expectRevert(bytes("bad wallet"));
        identity.setAgentWallet(agentId, address(0), deadline, hex"");
    }

    function test_UnsetAgentWallet() public {
        uint256 agentId = _register(alice, "ipfs://a");
        assertEq(identity.getAgentWallet(agentId), alice);

        vm.prank(alice);
        identity.unsetAgentWallet(agentId);
        assertEq(identity.getAgentWallet(agentId), address(0));
    }

    function test_AgentWalletClearedOnTransfer() public {
        uint256 agentId = _register(alice, "ipfs://a");
        uint256 deadline = block.timestamp + 60;
        bytes memory sig = _signAgentWallet(bobPk, agentId, bob, alice, deadline);
        vm.prank(alice);
        identity.setAgentWallet(agentId, bob, deadline, sig);
        assertEq(identity.getAgentWallet(agentId), bob);

        vm.prank(alice);
        identity.transferFrom(alice, carol, agentId);

        assertEq(identity.ownerOf(agentId), carol);
        assertEq(identity.getAgentWallet(agentId), address(0), "new owner must re-verify the wallet");
    }

    // ── authorization surface used by the other registries ───────────────────

    function test_IsAuthorizedOrOwner() public {
        uint256 agentId = _register(alice, "ipfs://a");
        assertTrue(identity.isAuthorizedOrOwner(alice, agentId));
        assertFalse(identity.isAuthorizedOrOwner(bob, agentId));

        vm.prank(alice);
        identity.setApprovalForAll(bob, true);
        assertTrue(identity.isAuthorizedOrOwner(bob, agentId));
    }

    function test_RevertWhen_IsAuthorizedOrOwnerOnUnknownAgent() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 42));
        identity.isAuthorizedOrOwner(alice, 42);
    }

    function test_ERC721Metadata() public view {
        assertEq(identity.name(), "AgentIdentity");
        assertEq(identity.symbol(), "AGENT");
        assertEq(identity.getVersion(), "2.0.0");
    }
}
