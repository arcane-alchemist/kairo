// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EventRegistry} from "./EventRegistry.sol";
import {NFT} from "./NFT.sol";

/// Lets attendees claim their POAP.

/// Claim flow:
///      1. The attendee presents a claim code (a unique link for RSVPs, a shared code for walk-ins).
///      2. The backend validates the code off-chain, then signs a voucher (eventId, claimer, deadline).
///      3. Anyone submits the voucher here, so a relayer can pay gas for the attendee.
///      4. This contract verifies the signature and the event state, then mints through NFT.
///      Codes and supply caps live in the backend; the chain enforces one claim per wallet per event.
contract Drop is EIP712, Ownable {
    bytes32 private constant CLAIM_TYPEHASH =
        keccak256("Claim(uint256 eventId,address claimer,uint256 deadline)");

    EventRegistry public immutable registry;
    NFT public immutable nft;
    address public signer; // backend key that signs vouchers

    mapping(uint256 => mapping(address => bool)) public hasClaimed; // eventId => claimer => claimed

    event Claimed(uint256 indexed eventId, address indexed claimer, uint256 indexed tokenId);
    event SignerUpdated(address indexed signer);

    error ZeroAddress();
    error VoucherExpired();
    error AlreadyClaimed();
    error EventNotActive();
    error EventNotStarted();
    error InvalidSignature();

    constructor(EventRegistry _registry, NFT _nft, address _signer)
        EIP712("Kairo Drop", "1")
        Ownable(msg.sender)
    {
        if (_signer == address(0)) revert ZeroAddress();
        registry = _registry;
        nft = _nft;
        signer = _signer;
    }

    /// Used to rotate the backend key if it leaks. Vouchers from the old key stop working.
    function setSigner(address _signer) external onlyOwner {
        if (_signer == address(0)) revert ZeroAddress();
        signer = _signer;
        emit SignerUpdated(_signer);
    }

    /// Claims are open from the event's startTime until the organizer deactivates it
    ///      (or the voucher deadline passes). endTime does not close claims.
    function claim(uint256 eventId, address claimer, uint256 deadline, bytes calldata signature)
        external
        returns (uint256 tokenId)
    {
        if (block.timestamp > deadline) revert VoucherExpired();
        if (hasClaimed[eventId][claimer]) revert AlreadyClaimed();

        EventRegistry.EventInfo memory info = registry.getEvent(eventId); // reverts if unknown
        if (!info.active) revert EventNotActive();
        if (block.timestamp < info.startTime) revert EventNotStarted();

        // The signed data binds the voucher to one event, one wallet and one deadline
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(CLAIM_TYPEHASH, eventId, claimer, deadline))
        );
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || recovered != signer) revert InvalidSignature();

        hasClaimed[eventId][claimer] = true; // set before minting
        tokenId = nft.mint(claimer, eventId);

        emit Claimed(eventId, claimer, tokenId);
    }
}