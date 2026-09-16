// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.t.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ReputationRegistryTest is Base {
    uint256 internal agentId;

    function setUp() public override {
        super.setUp();
        agentId = _register(alice, "ipfs://agent");
    }

    function _feedback(address client, int128 value, uint8 decimals, string memory tag1, string memory tag2) internal {
        vm.prank(client);
        reputation.giveFeedback(agentId, value, decimals, tag1, tag2, "", "", bytes32(0));
    }

    function test_KnowsItsIdentityRegistry() public view {
        assertEq(reputation.getIdentityRegistry(), address(identity));
    }

    function test_GiveFeedback() public {
        _feedback(bob, 9977, 2, "quality", "fast");

        (int128 value, uint8 decimals, string memory tag1, string memory tag2, bool revoked) =
            reputation.readFeedback(agentId, bob, 1);

        assertEq(value, 9977);
        assertEq(decimals, 2);
        assertEq(tag1, "quality");
        assertEq(tag2, "fast");
        assertFalse(revoked);
        assertEq(reputation.getLastIndex(agentId, bob), 1);
    }

    function test_AcceptsNegativeAndZeroValues() public {
        _feedback(bob, -500, 0, "", "");
        _feedback(carol, 0, 0, "", "");

        (int128 negative,,,,) = reputation.readFeedback(agentId, bob, 1);
        (int128 zero,,,,) = reputation.readFeedback(agentId, carol, 1);
        assertEq(negative, -500);
        assertEq(zero, 0);
    }

    function test_RevertWhen_AgentOwnerRatesThemselves() public {
        vm.prank(alice);
        vm.expectRevert(bytes("Self-feedback not allowed"));
        reputation.giveFeedback(agentId, 100, 0, "", "", "", "", bytes32(0));
    }

    function test_RevertWhen_OperatorRatesTheirOwnAgent() public {
        vm.prank(alice);
        identity.setApprovalForAll(bob, true);

        vm.prank(bob);
        vm.expectRevert(bytes("Self-feedback not allowed"));
        reputation.giveFeedback(agentId, 100, 0, "", "", "", "", bytes32(0));
    }

    function test_RevertWhen_AgentDoesNotExist() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 777));
        reputation.giveFeedback(777, 100, 0, "", "", "", "", bytes32(0));
    }

    function test_RevertWhen_TooManyDecimals() public {
        vm.prank(bob);
        vm.expectRevert(bytes("too many decimals"));
        reputation.giveFeedback(agentId, 100, 19, "", "", "", "", bytes32(0));
    }

    function test_RevertWhen_ValueOutOfRange() public {
        vm.prank(bob);
        vm.expectRevert(bytes("value too large"));
        reputation.giveFeedback(agentId, 1e38 + 1, 0, "", "", "", "", bytes32(0));

        vm.prank(bob);
        vm.expectRevert(bytes("value too large"));
        reputation.giveFeedback(agentId, -1e38 - 1, 0, "", "", "", "", bytes32(0));
    }

    function test_TracksMultipleFeedbacksFromSameClient() public {
        _feedback(bob, 10, 0, "a", "");
        _feedback(bob, 20, 0, "b", "");
        _feedback(bob, 30, 0, "c", "");

        assertEq(reputation.getLastIndex(agentId, bob), 3);
        (int128 second,,,,) = reputation.readFeedback(agentId, bob, 2);
        assertEq(second, 20);
    }

    function test_GetLastIndexIsZeroForSilentClient() public view {
        assertEq(reputation.getLastIndex(agentId, carol), 0);
    }

    function test_RevertWhen_ReadingOutOfBoundsIndex() public {
        _feedback(bob, 10, 0, "", "");

        vm.expectRevert(bytes("index out of bounds"));
        reputation.readFeedback(agentId, bob, 2);

        vm.expectRevert(bytes("index must be > 0"));
        reputation.readFeedback(agentId, bob, 0);
    }

    // ── revocation ───────────────────────────────────────────────────────────

    function test_RevokeFeedback() public {
        _feedback(bob, 10, 0, "", "");

        vm.prank(bob);
        reputation.revokeFeedback(agentId, 1);

        (,,,, bool revoked) = reputation.readFeedback(agentId, bob, 1);
        assertTrue(revoked);
    }

    function test_RevertWhen_RevokingTwice() public {
        _feedback(bob, 10, 0, "", "");
        vm.startPrank(bob);
        reputation.revokeFeedback(agentId, 1);
        vm.expectRevert(bytes("Already revoked"));
        reputation.revokeFeedback(agentId, 1);
        vm.stopPrank();
    }

    function test_RevertWhen_RevokingSomeoneElsesFeedback() public {
        _feedback(bob, 10, 0, "", "");
        // carol has no feedback, so index 1 is out of bounds for her
        vm.prank(carol);
        vm.expectRevert(bytes("index out of bounds"));
        reputation.revokeFeedback(agentId, 1);
    }

    function test_RevokedFeedbackIsExcludedFromSummary() public {
        _feedback(bob, 100, 0, "", "");
        _feedback(carol, 50, 0, "", "");

        vm.prank(bob);
        reputation.revokeFeedback(agentId, 1);

        (uint64 count, int128 summary,) = reputation.getSummary(agentId, _addrs(bob, carol), "", "");
        assertEq(count, 1);
        assertEq(summary, 50);
    }

    // ── responses ────────────────────────────────────────────────────────────

    function test_AppendResponse() public {
        _feedback(bob, 10, 0, "", "");

        vm.prank(carol);
        reputation.appendResponse(agentId, bob, 1, "ipfs://response", bytes32(uint256(1)));

        assertEq(reputation.getResponseCount(agentId, bob, 1, _noAddrs()), 1);
    }

    function test_RevertWhen_ResponseURIIsEmpty() public {
        _feedback(bob, 10, 0, "", "");
        vm.prank(carol);
        vm.expectRevert(bytes("Empty URI"));
        reputation.appendResponse(agentId, bob, 1, "", bytes32(0));
    }

    function test_RevertWhen_RespondingToUnknownFeedback() public {
        vm.prank(carol);
        vm.expectRevert(bytes("index out of bounds"));
        reputation.appendResponse(agentId, bob, 1, "ipfs://r", bytes32(0));
    }

    function test_SameResponderCanRespondRepeatedly() public {
        _feedback(bob, 10, 0, "", "");
        vm.startPrank(carol);
        reputation.appendResponse(agentId, bob, 1, "ipfs://r1", bytes32(0));
        reputation.appendResponse(agentId, bob, 1, "ipfs://r2", bytes32(0));
        vm.stopPrank();

        assertEq(reputation.getResponseCount(agentId, bob, 1, _noAddrs()), 2);
    }

    function test_CanRespondToRevokedFeedback() public {
        _feedback(bob, 10, 0, "", "");
        vm.prank(bob);
        reputation.revokeFeedback(agentId, 1);

        vm.prank(carol);
        reputation.appendResponse(agentId, bob, 1, "ipfs://r", bytes32(0));
        assertEq(reputation.getResponseCount(agentId, bob, 1, _noAddrs()), 1);
    }

    function test_ResponseCountAggregations() public {
        _feedback(bob, 10, 0, "", "");
        _feedback(bob, 20, 0, "", "");
        _feedback(carol, 30, 0, "", "");

        vm.startPrank(carol);
        reputation.appendResponse(agentId, bob, 1, "r", bytes32(0));
        reputation.appendResponse(agentId, bob, 2, "r", bytes32(0));
        vm.stopPrank();
        vm.prank(alice);
        reputation.appendResponse(agentId, carol, 1, "r", bytes32(0));

        // every response for the agent
        assertEq(reputation.getResponseCount(agentId, address(0), 0, _noAddrs()), 3);
        // every response on bob's feedback
        assertEq(reputation.getResponseCount(agentId, bob, 0, _noAddrs()), 2);
        // one specific feedback
        assertEq(reputation.getResponseCount(agentId, bob, 1, _noAddrs()), 1);
        // filtered by responder
        assertEq(reputation.getResponseCount(agentId, address(0), 0, _addrs(carol)), 2);
        assertEq(reputation.getResponseCount(agentId, address(0), 0, _addrs(alice)), 1);
    }

    // ── aggregation ──────────────────────────────────────────────────────────

    function test_SummaryAveragesValues() public {
        _feedback(bob, 100, 0, "", "");
        _feedback(carol, 50, 0, "", "");

        (uint64 count, int128 summary, uint8 decimals) = reputation.getSummary(agentId, _addrs(bob, carol), "", "");
        assertEq(count, 2);
        assertEq(summary, 75);
        assertEq(decimals, 0);
    }

    function test_SummaryNormalizesMixedDecimals() public {
        _feedback(bob, 9900, 2, "", ""); // 99.00
        _feedback(carol, 9700, 2, "", ""); // 97.00

        (uint64 count, int128 summary, uint8 decimals) = reputation.getSummary(agentId, _addrs(bob, carol), "", "");
        assertEq(count, 2);
        assertEq(summary, 9800); // 98.00
        assertEq(decimals, 2);
    }

    function test_RevertWhen_SummaryHasNoClientFilter() public {
        vm.expectRevert(bytes("clientAddresses required"));
        reputation.getSummary(agentId, _noAddrs(), "", "");
    }

    function test_SummaryIsZeroWhenNothingMatches() public view {
        (uint64 count, int128 summary, uint8 decimals) = reputation.getSummary(agentId, _addrs(bob), "", "");
        assertEq(count, 0);
        assertEq(summary, 0);
        assertEq(decimals, 0);
    }

    function test_SummaryFiltersByTags() public {
        _feedback(bob, 100, 0, "speed", "eu");
        _feedback(carol, 20, 0, "cost", "eu");

        (uint64 speedCount, int128 speedAvg,) = reputation.getSummary(agentId, _addrs(bob, carol), "speed", "");
        assertEq(speedCount, 1);
        assertEq(speedAvg, 100);

        (uint64 euCount,,) = reputation.getSummary(agentId, _addrs(bob, carol), "", "eu");
        assertEq(euCount, 2);

        (uint64 bothCount,,) = reputation.getSummary(agentId, _addrs(bob, carol), "cost", "eu");
        assertEq(bothCount, 1);

        // empty string on both tags is a wildcard, not a match on ""
        (uint64 allCount,,) = reputation.getSummary(agentId, _addrs(bob, carol), "", "");
        assertEq(allCount, 2);
    }

    function test_ReadAllFeedbackWithFilters() public {
        _feedback(bob, 10, 0, "speed", "eu");
        _feedback(bob, 20, 0, "cost", "us");
        _feedback(carol, 30, 0, "speed", "us");

        (address[] memory clients, uint64[] memory indexes, int128[] memory values,,,,) =
            reputation.readAllFeedback(agentId, _noAddrs(), "speed", "", false);

        assertEq(clients.length, 2);
        assertEq(clients[0], bob);
        assertEq(indexes[0], 1);
        assertEq(values[0], 10);
        assertEq(clients[1], carol);
        assertEq(values[1], 30);
    }

    function test_ReadAllFeedbackHonoursIncludeRevoked() public {
        _feedback(bob, 10, 0, "", "");
        _feedback(bob, 20, 0, "", "");
        vm.prank(bob);
        reputation.revokeFeedback(agentId, 1);

        (address[] memory visible,,,,,,) = reputation.readAllFeedback(agentId, _noAddrs(), "", "", false);
        assertEq(visible.length, 1);

        (address[] memory all,,,,,, bool[] memory revoked) =
            reputation.readAllFeedback(agentId, _noAddrs(), "", "", true);
        assertEq(all.length, 2);
        assertTrue(revoked[0]);
        assertFalse(revoked[1]);
    }

    function test_GetClientsReturnsUniqueAddresses() public {
        _feedback(bob, 10, 0, "", "");
        _feedback(bob, 20, 0, "", "");
        _feedback(carol, 30, 0, "", "");

        address[] memory clients = reputation.getClients(agentId);
        assertEq(clients.length, 2);
        assertEq(clients[0], bob);
        assertEq(clients[1], carol);
    }

    function test_Version() public view {
        assertEq(reputation.getVersion(), "2.0.0");
    }
}
