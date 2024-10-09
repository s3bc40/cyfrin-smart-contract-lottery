// unit
// integration
// forked
// staging -> mainet or testnet

// fuzzing
// Stateful fuzz
// stateless fuzz
// formal verification

// Challenge :
/* 
1. Unit tests - Basic tests that check the functionality;
2. Integration tests - We test our deployment scripts and other components of our contracts; --> THE GOAL
3. Forked tests - Pseudo staging;
4. Staging tests - We run tests on a mainnet/testnet;
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {Raffle} from "src/Raffle.sol";

contract InteractiondTest is Test, CodeConstants {
    /* Errors */
    // // cheated here error available in chainlink-brownie-contracts/contracts/src/v0.8/dev/vrf/SubscriptionAPI.sol
    error InvalidSubscription();
    error TooManyConsumers();

    /* Variables */
    HelperConfig helperConfig;
    CreateSubscription subscriptionContract;
    FundSubscription fundSubscription;
    AddConsumer addConsumer;

    /* Functions */
    function setUp() external {
        // Init all script contract to interact with
        helperConfig = new HelperConfig();
        subscriptionContract = new CreateSubscription();
        fundSubscription = new FundSubscription();
        addConsumer = new AddConsumer();
    }

    /*===============================================
                    HELPER CONFIG          
    ===============================================*/
    function testHelperConfigRevertWithInvalidChain() public {
        // Arrange
        uint256 chainId = 0;
        // Act / Assert
        vm.expectRevert(HelperConfig.HelperConfig__InvalidChainId.selector);
        helperConfig.getConfigByChainId(chainId);
    }

    function testHelperConfigGetSepoliaEthConfig() public {
        // Arrange
        uint256 chainId = ETH_SEPOLIA_CHAIN_ID;
        // Act
        HelperConfig.NetworkConfig memory config = helperConfig.getConfigByChainId(chainId);
        // Assert
        assertEq(config.entranceFee, 1e16);
        assertEq(config.interval, 30);
        assertEq(config.gasLane, 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae);
        assertEq(config.subscriptionId, 0);
        assertEq(config.callbackGasLimit, 500000);
        assertEq(config.vrfCoordinator, 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B);
        assertEq(config.link, 0x779877A7B0D9E8603169DdbD7836e478b4624789);
        assertEq(config.account, 0x44586c5784a07Cc85ae9f33FCf6275Ea41636A87);
    }

    /*===============================================
                     CREATE SUBSCRIPTION          
    ===============================================*/
    function testCreateSubscription() public {
        // Arrange
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        // Act
        (uint256 subscriptionId, address vrfCoordinator) =
            subscriptionContract.createSubscription(config.vrfCoordinator, config.account);
        // Assert
        assert(subscriptionId > 0);
        assertEq(vrfCoordinator, config.vrfCoordinator);
    }

    function testCreateSubscriptionUsingConfig() public {
        // Arrange / Act
        (uint256 subscriptionId, address vrfCoordinator) = subscriptionContract.run();
        // Assert
        assert(subscriptionId > 0);
        assert(vrfCoordinator != address(0));
    }

    /*===============================================
                     FUND SUBSCRIPTION          
    ===============================================*/
    function testFundSubscriptionRevertInvalidSubId() public {
        // Arrange / Act / Assert
        vm.expectRevert(InvalidSubscription.selector);
        fundSubscription.run();
    }

    function testFundSubscriptionEmitSubscriptionFunded() public {
        // Arrange
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        (config.subscriptionId, config.vrfCoordinator) =
            subscriptionContract.createSubscription(config.vrfCoordinator, config.account);
        // Act
        vm.recordLogs();
        fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // event SubscriptionFunded(uint256 indexed subId, uint256 oldBalance, uint256 newBalance);
        // @dev abi.decode data not indexed in event above to get the values from SubscriptionAPI.sol
        (, uint256 newBalance) = abi.decode(entries[0].data, (uint256, uint256));
        console.log("NewBalance: ", newBalance);
        // Assert
        assert(newBalance == fundSubscription.FUND_AMOUNT());
    }

    // @notice to keep in mind : vm.chainId(ETH_SEPOLIA_CHAIN_ID);

    /*===============================================
                     ADD CONSUMER          
    ===============================================*/
    // @dev test error TooManyConsumers(); MAX = 100
    // @notice might not happen since only one raffle is created
    function testAddConsumer() public {
        // Arrange
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        (config.subscriptionId, config.vrfCoordinator) =
            subscriptionContract.createSubscription(config.vrfCoordinator, config.account);
        fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);

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
        // Act
        vm.recordLogs();
        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subscriptionId, config.account);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // event SubscriptionConsumerAdded(uint256 indexed subId, address consumer);
        // @dev abi.decode data not indexed in event above to get the values from SubscriptionAPI.sol
        address consumer = abi.decode(entries[0].data, (address));
        console.log("Consumer: ", consumer);
        // Assert
        assert(consumer == address(raffle));
    }

    // function testAddConsumerUsingConfig() public {
    //     // Arrange
    //     HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
    //     (config.subscriptionId, config.vrfCoordinator) =
    //         subscriptionContract.createSubscription(config.vrfCoordinator, config.account);
    //     fundSubscription.fundSubscription(config.vrfCoordinator, config.subscriptionId, config.link, config.account);

    //     vm.startBroadcast(config.account);
    //     Raffle raffle = new Raffle(
    //         config.entranceFee,
    //         config.interval,
    //         config.vrfCoordinator,
    //         config.gasLane,
    //         config.subscriptionId,
    //         config.callbackGasLimit
    //     );
    //     vm.stopBroadcast();
    //     // Act
    //     vm.recordLogs();
    //     addConsumer.run();
    //     Vm.Log[] memory entries = vm.getRecordedLogs();
    //     // event SubscriptionConsumerAdded(uint256 indexed subId, address consumer);
    //     // @dev abi.decode data not indexed in event above to get the values from SubscriptionAPI.sol
    //     address consumer = abi.decode(entries[0].data, (address));
    //     console.log("Consumer: ", consumer);
    //     // Assert
    //     assert(consumer == address(raffle));
    // }
}
