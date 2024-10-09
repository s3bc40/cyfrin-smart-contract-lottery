// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        // local -> deploy mocks, get local config
        // sepolia -> get config from sepolia
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // To avoid InvalidConsumer error from VRF2.5Mock (modifier applied),
        // we need to check if a consumer is added from the subscrition id != 0
        if (config.subscriptionId == 0) {
            // create subscription
            CreateSubscription subscriptionContract = new CreateSubscription();
            (config.subscriptionId, config.vrfCoordinator) =
                subscriptionContract.createSubscription(config.vrfCoordinator, config.account);

            // Fund the subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        }

        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        // Add consumer
        AddConsumer addConsumer = new AddConsumer();
        // don't need broadcast here since we already broadcasted in the method
        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);

        return (raffle, helperConfig);
    }

    function run() public returns (Raffle, HelperConfig) {
        return deployContract();
    }
}
