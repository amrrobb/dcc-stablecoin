// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

library OracleLib {
    error OracleLib__StalePrice();
    error OracleLib__SequencerDown();
    error OracleLib__GracePeriodNotOver();

    uint256 private constant GRACE_PERIOD_TIME = 3600; // 1 hours

    /**
     * For information about heartbeat, see:
     * https://docs.chain.link/data-feeds#check-the-timestamp-of-the-latest-answer
     *
     * For a list of available Sequencer Uptime Feed proxy addresses, see:
     * https://docs.chain.link/docs/data-feeds/l2-sequencer-feeds
     */
    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed,
        uint256 heartbeat,
        address sequencerUptimeFeedAddress
    ) public view returns (int256) {
        if (sequencerUptimeFeedAddress != address(0)) {
            checkSesequencerUptimeFeed(AggregatorV2V3Interface(sequencerUptimeFeedAddress));
        }
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) revert OracleLib__StalePrice();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > heartbeat) revert OracleLib__StalePrice();

        return answer;
    }

    function checkSesequencerUptimeFeed(AggregatorV2V3Interface sequencerUptimeFeed) private view {
        (
            /*uint80 roundID*/
            ,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = sequencerUptimeFeed.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert OracleLib__SequencerDown();
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert OracleLib__GracePeriodNotOver();
        }
    }
}
