// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EventRegistry} from "./EventRegistry.sol";

/// A soulbound (ERC-5192) ERC-721 token.
///  Only the Drop contract can mint. There is no burn and no transfer, so an
///  attendance record is permanent. The art comes from the event, not the token:
///  every attendee of an event shares that event's metadata.
contract NFT is ERC721, Ownable {
    EventRegistry public immutable registry;
    address public minter; // the Drop contract

    uint256 private _nextTokenId = 1;

    mapping(uint256 => uint256) public tokenEvent; // tokenId => eventId

    event Locked(uint256 tokenId); // ERC-5192: tells wallets and marketplaces the token is non-transferable
    event MinterUpdated(address indexed minter);

    error Soulbound();
    error NotMinter();
    error EventNotFound();

    constructor(EventRegistry _registry) ERC721("Kairo Attendance", "KAIRO") Ownable(msg.sender) {
        registry = _registry;
    }

    ///  Called once after deployment to point this contract at Drop.
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    function mint(address to, uint256 eventId) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert NotMinter();
        // Without this check a token could point at a missing event and tokenURI would revert forever
        if (!registry.eventExists(eventId)) revert EventNotFound();

        tokenId = _nextTokenId++;
        tokenEvent[tokenId] = eventId;
        _mint(to, tokenId);

        emit Locked(tokenId);
    }

    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    ///  Returns the organizer's metadata URI for the token's event.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return registry.getEvent(tokenEvent[tokenId]).metadataURI;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == 0xb45a3c0e || super.supportsInterface(interfaceId); // ERC-5192
    }

    /// This is the whole soulbound mechanism. Every mint and transfer passes through here:
    ///      minting (token has no owner yet) is allowed, any later change of ownership reverts.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }
}