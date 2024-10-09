// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    /* Modifiers */
    modifier playerEnterRaffleWarpAndRoll() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); // best practice
        _;
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    /*===============================================
                    ENTER RAFFLE         
    ===============================================*/

    function testRaffleInitInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); // more readable via enum
    }

    function testRaffleRevertWhenNotPayingEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        /*
            Bools for
            - topic1 -> first indexed params
            - topic2 -> second indexed params
            - topic3 -> third indexed params
            - checkData -> if data not indexed
            - address that emit the event
        */
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterRaffleWhileRaffleCalculating() public playerEnterRaffleWarpAndRoll {
        // Arrange
        raffle.performUpkeep("");
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
    }

    /*===============================================
                     CHECK UPKEEP          
    ===============================================*/
    function testCheckUpkeepReturnsFalseIfNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); // best practice
        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public playerEnterRaffleWarpAndRoll {
        // Arrange
        raffle.performUpkeep("");
        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(!upKeepNeeded);
    }

    /* Challenges */
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public playerEnterRaffleWarpAndRoll {
        // Arrange
        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(upKeepNeeded);
    }

    /*===============================================
                     PERFORM UPKEEP          
    ===============================================*/
    function testPerformUpkeepRunWhenCheckUpkeepTrue() public playerEnterRaffleWarpAndRoll {
        // Arrange
        // Act / Assert
        raffle.performUpkeep("");
    }

    /* BONUS perform upkeep not needed DONE */
    function testPerformUpkeepRevertWhenUpkeepFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rstate = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rstate)
        );
        raffle.performUpkeep("");
    }

    // get data from emitted events in tests ?
    function testPerformUpkeepUpdateRaffleStateAndEmitRequestedId() public playerEnterRaffleWarpAndRoll {
        // Arrange
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        /* 
        struct Log {
            // The topics of the log, including the signature, if any.
            bytes32[] topics;
            // The raw data of the log.
            bytes data;
            // The address of the log's emitter.
            address emitter;
        }
        */
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // topics 0 is reserved (to learn later)
        // entries 1 since event emitted in vrfCoordinator
        bytes32 requestId = entries[1].topics[1];
        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(raffleState == Raffle.RaffleState.CALCULATING);
    }

    /*===============================================
                     FULFILLRANDOMWORDS          
    ===============================================*/
    // @notice stateless fuzz test for random words
    function testFulfillRandomWordsOnlyCalledAfterPerformUpkeep(uint256 randomRequestId) public skipFork {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPickAWinnerResetAndSendsMoney() public playerEnterRaffleWarpAndRoll skipFork {
        // Arrange
        uint256 additionalEntrants = 3; // 4 totals
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimestamp = raffle.getLastTimestamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimestamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimestamp > startingTimestamp);
    }
}
