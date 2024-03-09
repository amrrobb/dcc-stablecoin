// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {Test, console} from "forge-std/Test.sol";
import {OracleLib, AggregatorV3Interface, AggregatorV2V3Interface} from "../../contracts/libraries/OracleLib.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    uint8 private constant DECIMALS = 8;
    int256 private constant INTIAL_PRICE = 200 ether;
    // Answer == 0: Sequencer is up
    int256 private constant SEQUENCER_ANSWER_DOWN = 1;
    // Answer == 1: Sequencer is down
    int256 private constant SEQUENCER_ANSWER_UP = 0;
    uint256 private constant GRACE_PERIOD_TIME = 3600; // 1 hours

    MockV3Aggregator mockPriceFeed; // priceFeed
    MockV3Aggregator mockSequencerUptimeFeed; // sequencerUptimeFeed

    function setUp() public {
        mockPriceFeed = new MockV3Aggregator(DECIMALS, INTIAL_PRICE);
        mockSequencerUptimeFeed = new MockV3Aggregator(DECIMALS, SEQUENCER_ANSWER_DOWN);
    }

    // Without Sequencer
    function testRevertOnStaleCheck() public {
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 1);

        (,,, uint256 updatedAt,) = mockPriceFeed.latestRoundData();
        // secondsSince must be less than heartbeats
        uint256 secondsSince = block.timestamp - updatedAt;
        uint256 heartbeat = secondsSince - 1;

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(mockPriceFeed)).staleCheckLatestRoundData(heartbeat, address(0));
    }

    function testRevertOnBadAnswer() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        mockPriceFeed.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(mockPriceFeed)).staleCheckLatestRoundData(0, address(0));
    }

    // With Sequencer
    function testRevertOnSequencerDown() public {
        vm.expectRevert(OracleLib.OracleLib__SequencerDown.selector);
        AggregatorV3Interface(address(mockPriceFeed)).staleCheckLatestRoundData(1, address(mockSequencerUptimeFeed));
    }

    function testRevertOnGracePeriodNotOver() public {
        vm.warp(block.timestamp + GRACE_PERIOD_TIME - 1);
        vm.roll(block.number + 1);

        uint80 _roundId = 0;
        int256 _answer = SEQUENCER_ANSWER_UP;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        mockSequencerUptimeFeed.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__GracePeriodNotOver.selector);
        AggregatorV3Interface(address(mockPriceFeed)).staleCheckLatestRoundData(1, address(mockSequencerUptimeFeed));
    }
}
