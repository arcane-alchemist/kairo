// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EventRegistry} from "../src/EventRegistry.sol";
import {NFT} from "../src/NFT.sol";

contract NFTTest is Test {
    EventRegistry registry;
    NFT nft;

    address owner = makeAddr("owner");
    address drop = makeAddr("drop");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant URI = "ipfs://event-one-metadata";
    uint256 eventId;

    event Locked(uint256 tokenId);

    function setUp() public {
        registry = new EventRegistry();
        eventId = registry.createEvent("Kairo Launch Night", URI, 1_800_000_000, 1_800_003_600);

        vm.startPrank(owner);
        nft = new NFT(registry);
        nft.setMinter(drop);
        vm.stopPrank();
    }

    function _mint(address to) internal returns (uint256) {
        vm.prank(drop);
        return nft.mint(to, eventId);
    }

    function test_mint_assignsTokenToRecipient() public {
        uint256 tokenId = _mint(alice);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.tokenEvent(tokenId), eventId);
    }

    function test_mint_emitsLocked() public {
        vm.expectEmit(false, false, false, true);
        emit Locked(1);
        _mint(alice);
    }

    function test_mint_idsIncrement() public {
        assertEq(_mint(alice), 1);
        assertEq(_mint(bob), 2);
        assertEq(_mint(alice), 3);
        assertEq(nft.balanceOf(alice), 2);
    }

    function test_mint_revertsForNonMinter() public {
        vm.prank(alice);
        vm.expectRevert(NFT.NotMinter.selector);
        nft.mint(alice, eventId);
    }

    function test_mint_revertsForUnknownEvent() public {
        vm.prank(drop);
        vm.expectRevert(NFT.EventNotFound.selector);
        nft.mint(alice, 999);
    }

    function test_setMinter_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.setMinter(alice);

        vm.prank(owner);
        nft.setMinter(bob);
        assertEq(nft.minter(), bob);
    }

    function test_transferFrom_reverts() public {
        uint256 tokenId = _mint(alice);

        vm.prank(alice);
        vm.expectRevert(NFT.Soulbound.selector);
        nft.transferFrom(alice, bob, tokenId);

        assertEq(nft.ownerOf(tokenId), alice);
    }

    function test_safeTransferFrom_reverts() public {
        uint256 tokenId = _mint(alice);

        vm.prank(alice);
        vm.expectRevert(NFT.Soulbound.selector);
        nft.safeTransferFrom(alice, bob, tokenId);
    }

    function test_transferByApprovedOperator_reverts() public {
        uint256 tokenId = _mint(alice);

        vm.startPrank(alice);
        nft.approve(bob, tokenId);
        nft.setApprovalForAll(bob, true);
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(NFT.Soulbound.selector);
        nft.transferFrom(alice, bob, tokenId);
    }

    function test_tokenURI_returnsEventMetadata() public {
        uint256 tokenId = _mint(alice);
        assertEq(nft.tokenURI(tokenId), URI);
    }

    function test_tokenURI_revertsForUnknownToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.tokenURI(1);
    }

    function test_locked_isTrueForExistingToken() public {
        uint256 tokenId = _mint(alice);
        assertTrue(nft.locked(tokenId));
    }

    function test_locked_revertsForUnknownToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.locked(1);
    }

    function test_supportsInterface() public view {
        assertTrue(nft.supportsInterface(0xb45a3c0e)); // ERC-5192
        assertTrue(nft.supportsInterface(0x80ac58cd)); // ERC-721
        assertTrue(nft.supportsInterface(0x5b5e139f)); // ERC-721 Metadata
        assertFalse(nft.supportsInterface(0xffffffff));
    }

    function testFuzz_transferAlwaysReverts(address to) public {
        vm.assume(to != address(0) && to != alice);
        uint256 tokenId = _mint(alice);

        vm.prank(alice);
        vm.expectRevert(NFT.Soulbound.selector);
        nft.transferFrom(alice, to, tokenId);
    }
}