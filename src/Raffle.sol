// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations -> enums
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle contract
 * @author s3bc40
 * @notice This contract is for creating a sample raffle
 * @dev Implementd Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TansferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playerLength, uint256 raffleState);

    /* Type declarations */
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1

    }

    /* State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee; // constant vs immutable -> init at constructor
    // @dev Duration of the lottery in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address payable private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    /* @notice Inherited code base should init the parent constructor */
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimestamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        // require(msg.value >= i_entranceFee, "Insufficient ETH");
        //require(msg.value >= i_entranceFee, Raffle__SendMoreToEnterRaffle());
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // Event allows to make migration and front end indexing easier
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink nodes will call to see
     * if the lottery is ready to pick a winner.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle
     * 2. Lottery is open
     * 3. The contract has ETH
     * 4. Implicitly, your subscuription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it is time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(bytes memory /*checkData*/ )
        public
        view
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */ // soliduty syntax feat: call in func return auto
        )
    {
        /* Check */
        bool timeHasPassed = ((block.timestamp - s_lastTimestamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, ""); // for clarity set return
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        // @notice Redundant with VRFCoordinatorV2_5Mock.sol RandomWordsRequested event. just for the course
        emit RequestedRaffleWinner(requestId);
    }

    /**
     * @notice Fulfill a random word request from the VRF coordinator
     * @dev This function should be called by the VRF coordinator (VRFConsumerBaseV2Plus virtual)
     * @dev CEI : Checks, Effects, Interactions
     */
    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        // Checks -> conditionals

        // Effect (Internal Contract state)
        /* To always get a random winner index between 0 and s_players.length - 1 */
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        // Interactions (External Contract interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TansferFailed();
        }
    }

    /**
     * Getter functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 index) external view returns (address payable) {
        return s_players[index];
    }

    function getRecentWinner() external view returns (address payable) {
        return s_recentWinner;
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimestamp;
    }
}
