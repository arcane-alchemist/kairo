// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EventRegistry} from "../src/EventRegistry.sol";
import {NFT} from "../src/NFT.sol";
import {Drop} from "../src/Drop.sol";

contract DropTest is Test {
    EventRegistry registry;
    NFT nft;
    Drop drop;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address relayer = makeAddr("relayer");

    uint256 signerKey = 0xA11CE;
    address signer = vm.addr(0xA11CE);

    uint256 constant START = 1_800_000_000;
    uint256 constant END = 1_800_003_600;
    string constant URI = "ipfs://event-one-metadata";

    uint256 eventId;
    uint256 deadline;

    event Claimed(uint256 indexed eventId, address indexed claimer, uint256 indexed tokenId);

    function setUp() public {
        registry = new EventRegistry();
        eventId = registry.createEvent("Kairo Launch Night", URI, START, END);

        vm.startPrank(owner);
        nft = new NFT(registry);
        drop = new Drop(registry, nft, signer);
        nft.setMinter(address(drop));
        vm.stopPrank();

        vm.warp(START + 1);
        deadline = block.timestamp + 1 days;
    }

    function _sign(uint256 key, uint256 id, address claimer, uint256 dl) internal view returns (bytes memory) {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Kairo Drop"),
                keccak256("1"),
                block.chainid,
                address(drop)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(keccak256("Claim(uint256 eventId,address claimer,uint256 deadline)"), id, claimer, dl)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, keccak256(abi.encodePacked("\x19\x01", domain, structHash)));
        return abi.encodePacked(r, s, v);
    }

    function _claim(address claimer) internal returns (uint256) {
        return drop.claim(eventId, claimer, deadline, _sign(signerKey, eventId, claimer, deadline));
    }

    function test_claim_mintsSoulboundTokenToClaimer() public {
        uint256 tokenId = _claim(alice);

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.tokenEvent(tokenId), eventId);
        assertEq(nft.tokenURI(tokenId), URI);
        assertTrue(drop.hasClaimed(eventId, alice));

        vm.prank(alice);
        vm.expectRevert(NFT.Soulbound.selector);
        nft.transferFrom(alice, bob, tokenId);
    }

    function test_claim_emitsClaimed() public {
        vm.expectEmit(true, true, true, false);
        emit Claimed(eventId, alice, 1);
        _claim(alice);
    }

    function test_claim_canBeRelayedByAnyone() public {
        vm.prank(relayer);
        uint256 tokenId = _claim(alice);
        assertEq(nft.ownerOf(tokenId), alice);
    }

    function test_claim_revertsOnDoubleClaim() public {
        _claim(alice);
        vm.expectRevert(Drop.AlreadyClaimed.selector);
        _claim(alice);
    }

    function test_claim_differentClaimersSameEvent() public {
        _claim(alice);
        _claim(bob);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.balanceOf(bob), 1);
    }

    function test_claim_sameClaimerDifferentEvents() public {
        uint256 second = registry.createEvent("Second Event", "ipfs://two", START, END);
        _claim(alice);
        drop.claim(second, alice, deadline, _sign(signerKey, second, alice, deadline));
        assertEq(nft.balanceOf(alice), 2);
    }

    function test_claim_revertsForWrongSigner() public {
        bytes memory sig = _sign(0xBAD, eventId, alice, deadline);
        vm.expectRevert(Drop.InvalidSignature.selector);
        drop.claim(eventId, alice, deadline, sig);
    }

    function test_claim_revertsForMalformedSignature() public {
        vm.expectRevert(Drop.InvalidSignature.selector);
        drop.claim(eventId, alice, deadline, hex"1234");
    }

    function test_claim_voucherBoundToClaimer() public {
        bytes memory sig = _sign(signerKey, eventId, alice, deadline);
        vm.expectRevert(Drop.InvalidSignature.selector);
        drop.claim(eventId, bob, deadline, sig);
    }

    function test_claim_voucherBoundToEvent() public {
        uint256 second = registry.createEvent("Second Event", "ipfs://two", START, END);
        bytes memory sig = _sign(signerKey, eventId, alice, deadline);
        vm.expectRevert(Drop.InvalidSignature.selector);
        drop.claim(second, alice, deadline, sig);
    }

    function test_claim_voucherBoundToDeadline() public {
        bytes memory sig = _sign(signerKey, eventId, alice, deadline);
        vm.expectRevert(Drop.InvalidSignature.selector);
        drop.claim(eventId, alice, deadline + 1, sig);
    }

    function test_claim_revertsAfterDeadline() public {
        bytes memory sig = _sign(signerKey, eventId, alice, deadline);
        vm.warp(deadline + 1);
        vm.expectRevert(Drop.VoucherExpired.selector);
        drop.claim(eventId, alice, deadline, sig);
    }

    function test_claim_worksExactlyAtDeadline() public {
        bytes memory sig = _sign(signerKey, eventId, alice, deadline);
        vm.warp(deadline);
        drop.claim(eventId, alice, deadline, sig);
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_claim_revertsBeforeEventStarts() public {
        uint256 future =
            registry.createEvent("Later", "ipfs://later", block.timestamp + 1 days, block.timestamp + 2 days);
        vm.expectRevert(Drop.EventNotStarted.selector);
        drop.claim(future, alice, deadline, _sign(signerKey, future, alice, deadline));
    }

    function test_claim_worksAfterEventEnds() public {
        vm.warp(END + 1 hours);
        uint256 dl = block.timestamp + 1 days;
        drop.claim(eventId, alice, dl, _sign(signerKey, eventId, alice, dl));
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_claim_revertsWhenEventDeactivated() public {
        registry.deactivateEvent(eventId);
        vm.expectRevert(Drop.EventNotActive.selector);
        _claim(alice);
    }

    function test_claim_revertsForUnknownEvent() public {
        bytes memory sig = _sign(signerKey, 999, alice, deadline);
        vm.expectRevert(EventRegistry.EventNotFound.selector);
        drop.claim(999, alice, deadline, sig);
    }

    function test_setSigner_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        drop.setSigner(alice);
    }

    function test_setSigner_rotatesKey() public {
        address newSigner = vm.addr(0xB0B);
        vm.prank(owner);
        drop.setSigner(newSigner);

        bytes memory oldSig = _sign(signerKey, eventId, alice, deadline);
        vm.expectRevert(Drop.InvalidSignature.selector);
        drop.claim(eventId, alice, deadline, oldSig);

        drop.claim(eventId, alice, deadline, _sign(0xB0B, eventId, alice, deadline));
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_constructor_revertsOnZeroSigner() public {
        vm.expectRevert(Drop.ZeroAddress.selector);
        new Drop(registry, nft, address(0));
    }

    function test_setSigner_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Drop.ZeroAddress.selector);
        drop.setSigner(address(0));
    }

    function testFuzz_claim_anyClaimer(address claimer) public {
        vm.assume(claimer != address(0));
        uint256 tokenId = _claim(claimer);
        assertEq(nft.ownerOf(tokenId), claimer);
    }
}
