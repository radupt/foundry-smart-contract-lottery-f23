// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Events */
    event EnterRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player"); // starting user
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        (, , , , , , , deployerKey) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE); // to give to the player some money
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN); // initialize the Raffle state to OPEN
    }

    ////////////////
    // enterRaffle
    ///////////////

    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER); //pretend to be that player
        //Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle(); // it pass because it reverts as we expect
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle)); // check the documentation for this false stuf
        emit EnterRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        // we need a subscription
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        // to be shure that we entered the raffle, we hato to performUpkeep, and put the state in CALCULATING
        vm.warp(block.timestamp + interval + 1); // to be shure we are over the interval
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // here it should be in a calculating state

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}(); // should revert because in calculatin
    }

    /////////////////////////
    //checkupkeep
    ////////////////////////

    function testCheckUpkeepReturnsFalseIfIthasNoBalance() public {
        // Arange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded); // assert not false
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        // Arange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp);
        vm.roll(block.number + 1);

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded == true);
    }

    ////////////////////////
    /// performUpkeep
    ///////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act/assert
        raffle.performUpkeep("");
    }

    /*
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        // Act/Assert
        vm.expectRevert(
            abi.encodeWithSelector( // expecting this transaction to fail with this error code with this parameters
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }*/
    /*
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }
*/
    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // What if i need to test using the output of an event?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        // Act
        vm.recordLogs(); // this function tells the VM to start recording all the emited events. To access them use getRecordedLogs
        raffle.performUpkeep(""); // emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); // whitch is going to get all of the values of all of the events recently emited
        // logs are recorded as bytes32
        bytes32 requestId = entries[1].topics[1]; // is gonna be the second event, topics 1 because is the request id

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1); // calculating
    }

    ////////////////////////
    // fulfullRandomWords //
    ////////////////////////

    modifier skipFork() {
        if (block.chainid != 31337) {
            return; // se non è questo non farlo
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed skipFork {
        // Arrange
        // This is where we're going to try to have the mock actually call fulfillrandomwords and it should fail
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId, // foundry will create a random number for this and call this test many times with many random numbers
            address(raffle)
        ); // we need to make sure that no matter we pass this is gonna fail
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); // raffle players enter, so create player (address(1))
            hoax(player, STARTING_USER_BALANCE); // to give to the player 1 ether
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        // pretend to be chainlink vrf to get random number & pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId), // foundry will create a random number for this and call this test many times with many random numbers
            address(raffle)
        );

        //assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLenghtOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(
            raffle.getRecentWinner().balance ==
                STARTING_USER_BALANCE + prize - entranceFee
        );
    }
}

// forge test --match-contract RaffleTest --match-test testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney
