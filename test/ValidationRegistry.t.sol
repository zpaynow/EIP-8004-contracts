// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base} from "./Base.t.sol";

contract ValidationRegistryTest is Base {
    uint256 internal agentId;
    bytes32 internal constant REQUEST_HASH = keccak256("request-1");

    function setUp() public override {
        super.setUp();
        agentId = _register(alice, "ipfs://agent");
    }

    function _request(bytes32 requestHash) internal {
        vm.prank(alice);
        validation.validationRequest(validator, agentId, "ipfs://request", requestHash);
    }

    function test_KnowsItsIdentityRegistry() public view {
        assertEq(validation.getIdentityRegistry(), address(identity));
    }

    function test_CreateValidationRequest() public {
        _request(REQUEST_HASH);

        (address validatorAddress, uint256 id, uint8 response,,, uint256 lastUpdate) =
            validation.getValidationStatus(REQUEST_HASH);

        assertEq(validatorAddress, validator);
        assertEq(id, agentId);
        assertEq(response, 0);
        assertEq(lastUpdate, block.timestamp);

        bytes32[] memory forAgent = validation.getAgentValidations(agentId);
        assertEq(forAgent.length, 1);
        assertEq(forAgent[0], REQUEST_HASH);

        bytes32[] memory forValidator = validation.getValidatorRequests(validator);
        assertEq(forValidator.length, 1);
        assertEq(forValidator[0], REQUEST_HASH);
    }

    function test_ApprovedOperatorCanRequest() public {
        vm.prank(alice);
        identity.approve(bob, agentId);

        vm.prank(bob);
        validation.validationRequest(validator, agentId, "ipfs://request", REQUEST_HASH);

        (address validatorAddress,,,,,) = validation.getValidationStatus(REQUEST_HASH);
        assertEq(validatorAddress, validator);
    }

    function test_RevertWhen_StrangerRequestsValidation() public {
        vm.prank(bob);
        vm.expectRevert(bytes("Not authorized"));
        validation.validationRequest(validator, agentId, "ipfs://request", REQUEST_HASH);
    }

    function test_RevertWhen_RequestHashReused() public {
        _request(REQUEST_HASH);
        vm.prank(alice);
        vm.expectRevert(bytes("exists"));
        validation.validationRequest(validator, agentId, "ipfs://request", REQUEST_HASH);
    }

    function test_RevertWhen_ValidatorIsZero() public {
        vm.prank(alice);
        vm.expectRevert(bytes("bad validator"));
        validation.validationRequest(address(0), agentId, "ipfs://request", REQUEST_HASH);
    }

    function test_SubmitValidationResponse() public {
        _request(REQUEST_HASH);

        vm.prank(validator);
        validation.validationResponse(REQUEST_HASH, 95, "ipfs://response", keccak256("evidence"), "tee");

        (,, uint8 response, bytes32 responseHash, string memory tag,) = validation.getValidationStatus(REQUEST_HASH);
        assertEq(response, 95);
        assertEq(responseHash, keccak256("evidence"));
        assertEq(tag, "tee");
    }

    function test_AcceptsBoundaryResponses() public {
        _request(REQUEST_HASH);
        vm.prank(validator);
        validation.validationResponse(REQUEST_HASH, 0, "ipfs://failed", bytes32(0), "");
        (,, uint8 failed,,,) = validation.getValidationStatus(REQUEST_HASH);
        assertEq(failed, 0);

        bytes32 second = keccak256("request-2");
        _request(second);
        vm.prank(validator);
        validation.validationResponse(second, 100, "ipfs://passed", bytes32(0), "");
        (,, uint8 passed,,,) = validation.getValidationStatus(second);
        assertEq(passed, 100);
    }

    function test_RevertWhen_NonValidatorResponds() public {
        _request(REQUEST_HASH);
        vm.prank(bob);
        vm.expectRevert(bytes("not validator"));
        validation.validationResponse(REQUEST_HASH, 50, "ipfs://r", bytes32(0), "");
    }

    function test_RevertWhen_ResponseAbove100() public {
        _request(REQUEST_HASH);
        vm.prank(validator);
        vm.expectRevert(bytes("resp>100"));
        validation.validationResponse(REQUEST_HASH, 101, "ipfs://r", bytes32(0), "");
    }

    function test_RevertWhen_RespondingToUnknownRequest() public {
        vm.prank(validator);
        vm.expectRevert(bytes("unknown"));
        validation.validationResponse(keccak256("nope"), 50, "ipfs://r", bytes32(0), "");
    }

    function test_RevertWhen_ReadingUnknownRequest() public {
        vm.expectRevert(bytes("unknown"));
        validation.getValidationStatus(keccak256("nope"));
    }

    function test_ValidatorCanOverwriteItsResponse() public {
        _request(REQUEST_HASH);
        vm.startPrank(validator);
        validation.validationResponse(REQUEST_HASH, 40, "ipfs://first", bytes32(0), "a");
        validation.validationResponse(REQUEST_HASH, 90, "ipfs://second", bytes32(0), "b");
        vm.stopPrank();

        (,, uint8 response,, string memory tag,) = validation.getValidationStatus(REQUEST_HASH);
        assertEq(response, 90);
        assertEq(tag, "b");
    }

    function test_SummaryAveragesAnsweredRequests() public {
        bytes32 first = keccak256("r1");
        bytes32 second = keccak256("r2");
        bytes32 unanswered = keccak256("r3");
        _request(first);
        _request(second);
        _request(unanswered);

        vm.startPrank(validator);
        validation.validationResponse(first, 80, "u", bytes32(0), "tee");
        validation.validationResponse(second, 100, "u", bytes32(0), "zk");
        vm.stopPrank();

        // unanswered requests are not counted
        (uint64 count, uint8 avg) = validation.getSummary(agentId, _noAddrs(), "");
        assertEq(count, 2);
        assertEq(avg, 90);

        // tag filter
        (uint64 teeCount, uint8 teeAvg) = validation.getSummary(agentId, _noAddrs(), "tee");
        assertEq(teeCount, 1);
        assertEq(teeAvg, 80);

        // validator filter
        (uint64 byValidator,) = validation.getSummary(agentId, _addrs(validator), "");
        assertEq(byValidator, 2);
        (uint64 byStranger,) = validation.getSummary(agentId, _addrs(bob), "");
        assertEq(byStranger, 0);
    }

    function test_Version() public view {
        assertEq(validation.getVersion(), "2.0.0");
    }
}
