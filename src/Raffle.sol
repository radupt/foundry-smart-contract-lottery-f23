// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
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
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// to install it: forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit

/**
 * @title A Sample Raffle Contract
 * @author Radu Petrici
 * @notice This contract if for creating a sample raffle
 * @dev Implemets Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    /**
     * Type declarations
     */

    // to keep monitorate the state of the contract
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /**
     * State Variables
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 3;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // duration of the lottery in seconds
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**
     * Events
     */
    event EnterRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    // what data structure should we use? How to keep track of all the players?

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) /* this for fulfillRandomWords */ {
        // to save it only once
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        //require(msg.value >= i_entranceFee, "Not enough ETH sent!");
        if (msg.value < i_entranceFee) {
            // more gas efficent
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender)); // payable to allow an address to get eth or whatever native token

        // Reasons for events
        //1. Makes migrations easier
        //2. Makes front end "indexing" easier
        emit EnterRaffle(msg.sender);
    }

    // When is the winner supposed to be picked?
    /**
     * @dev This is the function that Chainlink Automation nodes call to see if it's time to perform an upkeep.
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in OPEN state
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription is funded with LINK
     */
    function checkUpkeep(
        bytes memory /* checkData */ // function that tells when is time to call performUpkeep
    ) public view returns (bool upkeepNeeded, bytes memory /* performData*/ ) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState; // is a if
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 1. Get a random number
    // 2. Use the random number to pick a player
    // 3. Be automatically called

    function performUpkeep(bytes calldata /* performData */ ) external {
        (bool upkeepNeeded,) = checkUpkeep(""); // call this function the verify it
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, //
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    /*
    function pickWinner() external {
        // check to see if enough time has passed

        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, //
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        // 1. Request the RNG -- requesting the winner
        // 2. Get the random number -- piching the actual winner
    }
    */
    // when we are waiting for the random winner to be picked, we don't want anybody else to enter the raffle

    // CEI: Checks, Effects, Interactions
    function fulfillRandomWords(uint256, /*requestID*/ uint256[] memory randomWords) internal override {
        // for this function we need VRFConsumerBaseV2
        // function that the chainlink node is gonna call in order for us to get our random number back

        // 12 % 10 = 2

        // Checks
        // require (if -> errors)
        // Effects (Our own contract)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        // we want to reset the players array, starting at index 0
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);

        // Interactions (other contracts)
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Functions
     */

    function getEntraceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLenghtOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
