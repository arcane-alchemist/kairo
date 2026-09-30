// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {EventRegistry} from "../src/EventRegistry.sol";
import {NFT} from "../src/NFT.sol";
import {Drop} from "../src/Drop.sol";

/// PRIVATE_KEY (deployer) and SIGNER_ADDRESS (backend voucher signer, ideally
///      a different key from the deployer). The deployer becomes owner of NFT and Drop.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address signer = vm.envAddress("SIGNER_ADDRESS");

        vm.startBroadcast(deployerKey);

        EventRegistry registry = new EventRegistry();
        NFT nft = new NFT(registry);
        Drop drop = new Drop(registry, nft, signer);

        // Only Drop is allowed to mint POAPs
        nft.setMinter(address(drop));

        vm.stopBroadcast();

        // Only save addresses for real broadcasts, so a dry run never writes fake addresses
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            string memory key = "deployment";
            vm.serializeAddress(key, "eventRegistry", address(registry));
            vm.serializeAddress(key, "nft", address(nft));
            string memory json = vm.serializeAddress(key, "drop", address(drop));

            vm.createDir("./deployments", true);
            vm.writeJson(json, string.concat("./deployments/", vm.toString(block.chainid), ".json"));
        }
    }
}
