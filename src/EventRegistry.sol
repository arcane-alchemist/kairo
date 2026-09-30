// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///  A registry of events.
///  Events are created by users and are identified by a unique ID.
///  Each event has an organizer, a name, a metadata URI, and a time window.
///  The organizer is the user who created the event.
///  The metadata URI points to the event's custom art (an IPFS metadata URI).
///  Other contracts only read from here: Drop checks an event is active,
///  NFT reads its metadata. Anyone can create an event and becomes its organizer.
contract EventRegistry {
    struct EventInfo {
        uint256 eventId;
        address organizer;
        string name;
        string metadataURI; // ipfs:// link to a JSON file with name, description and image (the custom POAP art)
        uint256 startTime;
        uint256 endTime;
        bool active; // set to false by the organizer; not affected by endTime passing
    }

    uint256 private _nextEventId = 1; // ids start at 1, so 0 is never valid

    mapping(uint256 => EventInfo) private _events;
    mapping(address => uint256[]) private _organizerEvents; // lets a frontend list an organizer's events

    event EventCreated(
        uint256 indexed eventId,
        address indexed organizer,
        string name,
        string metadataURI,
        uint256 startTime,
        uint256 endTime
    );
    event EventDeactivated(uint256 indexed eventId);

    error EventNotFound();
    error NotOrganizer();
    error AlreadyInactive();
    error InvalidTimeRange();
    error EmptyName();
    error EmptyMetadataURI();

    /// The metadata URI cannot be changed later. Tokens read it live, so editing it
    ///      would change the art of tokens people have already claimed.
    function createEvent(
        string calldata name,
        string calldata metadataURI,
        uint256 startTime,
        uint256 endTime
    ) external returns (uint256 eventId) {
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(metadataURI).length == 0) revert EmptyMetadataURI();
        if (endTime <= startTime) revert InvalidTimeRange();

        eventId = _nextEventId++;

        _events[eventId] = EventInfo({
            eventId: eventId,
            organizer: msg.sender,
            name: name,
            metadataURI: metadataURI,
            startTime: startTime,
            endTime: endTime,
            active: true
        });

        _organizerEvents[msg.sender].push(eventId);

        emit EventCreated(eventId, msg.sender, name, metadataURI, startTime, endTime);
    }

    /// Permanent: there is no reactivation. Drop refuses claims for inactive events.
    function deactivateEvent(uint256 eventId) external {
        EventInfo storage info = _getExisting(eventId);

        if (info.organizer != msg.sender) revert NotOrganizer();
        if (!info.active) revert AlreadyInactive();

        info.active = false;

        emit EventDeactivated(eventId);
    }

    function getEvent(uint256 eventId) external view returns (EventInfo memory) {
        return _getExisting(eventId);
    }

    function getOrganizerEvents(address organizer) external view returns (uint256[] memory) {
        return _organizerEvents[organizer];
    }

    function eventExists(uint256 eventId) external view returns (bool) {
        return _events[eventId].organizer != address(0);
    }

    function isOrganizer(uint256 eventId, address account) external view returns (bool) {
        // address(0) is the organizer of every non-existent event, so exclude it
        return account != address(0) && _events[eventId].organizer == account;
    }

    /// Checks the organizer's flag only, not the event's time window.
    function isActive(uint256 eventId) external view returns (bool) {
        return _events[eventId].active;
    }

    function totalEvents() external view returns (uint256) {
        return _nextEventId - 1;
    }

    function _getExisting(uint256 eventId) internal view returns (EventInfo storage info) {
        info = _events[eventId];
        if (info.organizer == address(0)) revert EventNotFound();
    }
}