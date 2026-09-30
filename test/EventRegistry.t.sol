// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EventRegistry} from "../src/EventRegistry.sol";

contract EventRegistryTest is Test {
    EventRegistry registry;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    string constant NAME = "Kairo Launch Night";
    string constant URI = "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
    uint256 constant START = 1_800_000_000;
    uint256 constant END = 1_800_003_600;

    // Redeclared so vm.expectEmit can match them; must mirror EventRegistry exactly
    event EventCreated(
        uint256 indexed eventId,
        address indexed organizer,
        string name,
        string metadataURI,
        uint256 startTime,
        uint256 endTime
    );
    event EventDeactivated(uint256 indexed eventId);

    function setUp() public {
        registry = new EventRegistry();
    }

    function _create(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = registry.createEvent(NAME, URI, START, END);
    }

    function test_createEvent_storesData() public {
        uint256 id = _create(alice);

        assertEq(id, 1);
        EventRegistry.EventInfo memory e = registry.getEvent(id);
        assertEq(e.eventId, 1);
        assertEq(e.organizer, alice);
        assertEq(e.name, NAME);
        assertEq(e.metadataURI, URI);
        assertEq(e.startTime, START);
        assertEq(e.endTime, END);
        assertTrue(e.active);
    }

    function test_createEvent_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit EventCreated(1, alice, NAME, URI, START, END);
        _create(alice);
    }

    function test_createEvent_idsIncrementAcrossOrganizers() public {
        assertEq(_create(alice), 1);
        assertEq(_create(bob), 2);
        assertEq(_create(alice), 3);
        assertEq(registry.totalEvents(), 3);
    }

    function test_createEvent_tracksOrganizerEvents() public {
        _create(alice);
        _create(bob);
        _create(alice);

        uint256[] memory a = registry.getOrganizerEvents(alice);
        assertEq(a.length, 2);
        assertEq(a[0], 1);
        assertEq(a[1], 3);
        assertEq(registry.getOrganizerEvents(bob).length, 1);
    }

    function test_createEvent_revertsOnEmptyName() public {
        vm.expectRevert(EventRegistry.EmptyName.selector);
        registry.createEvent("", URI, START, END);
    }

    function test_createEvent_revertsOnEmptyURI() public {
        vm.expectRevert(EventRegistry.EmptyMetadataURI.selector);
        registry.createEvent(NAME, "", START, END);
    }

    function test_createEvent_revertsWhenEndEqualsStart() public {
        vm.expectRevert(EventRegistry.InvalidTimeRange.selector);
        registry.createEvent(NAME, URI, START, START);
    }

    function test_createEvent_revertsWhenEndBeforeStart() public {
        vm.expectRevert(EventRegistry.InvalidTimeRange.selector);
        registry.createEvent(NAME, URI, END, START);
    }

    function testFuzz_createEvent_timeRange(uint256 start, uint256 end) public {
        if (end <= start) {
            vm.expectRevert(EventRegistry.InvalidTimeRange.selector);
            registry.createEvent(NAME, URI, start, end);
        } else {
            uint256 id = registry.createEvent(NAME, URI, start, end);
            assertEq(registry.getEvent(id).endTime, end);
        }
    }

    function test_deactivate_works() public {
        uint256 id = _create(alice);
        assertTrue(registry.isActive(id));

        vm.expectEmit(true, false, false, false);
        emit EventDeactivated(id);
        vm.prank(alice);
        registry.deactivateEvent(id);

        assertFalse(registry.isActive(id));
        assertFalse(registry.getEvent(id).active);
    }

    function test_deactivate_revertsForNonOrganizer() public {
        uint256 id = _create(alice);
        vm.prank(bob);
        vm.expectRevert(EventRegistry.NotOrganizer.selector);
        registry.deactivateEvent(id);
    }

    function test_deactivate_revertsWhenAlreadyInactive() public {
        uint256 id = _create(alice);
        vm.startPrank(alice);
        registry.deactivateEvent(id);
        vm.expectRevert(EventRegistry.AlreadyInactive.selector);
        registry.deactivateEvent(id);
        vm.stopPrank();
    }

    function test_deactivate_revertsForUnknownEvent() public {
        vm.expectRevert(EventRegistry.EventNotFound.selector);
        registry.deactivateEvent(999);
    }

    function test_getEvent_revertsForUnknownEvent() public {
        vm.expectRevert(EventRegistry.EventNotFound.selector);
        registry.getEvent(1);
        vm.expectRevert(EventRegistry.EventNotFound.selector);
        registry.getEvent(0);
    }

    function test_eventExists() public {
        assertFalse(registry.eventExists(1));
        _create(alice);
        assertTrue(registry.eventExists(1));
        assertFalse(registry.eventExists(0));
    }

    function test_isOrganizer() public {
        uint256 id = _create(alice);
        assertTrue(registry.isOrganizer(id, alice));
        assertFalse(registry.isOrganizer(id, bob));
    }

    function test_isOrganizer_zeroAddressNeverMatchesUnknownEvent() public view {
        assertFalse(registry.isOrganizer(42, address(0)));
    }

    function test_isActive_falseForUnknownEvent() public view {
        assertFalse(registry.isActive(42));
    }

    function test_totalEvents_startsAtZero() public view {
        assertEq(registry.totalEvents(), 0);
    }
}
