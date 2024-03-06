// SPDX-License-Identifier:  MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
// import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// import {ERC20DecimalsMock} from "@openzeppelin/contracts/mocks/token/ERC20DecimalsMock.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
// import {MockV3Aggregator} from "../contracts/mocks/MockV3Aggregator.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address tokenAddress;
        address priceFeed;
        uint8 decimals;
        uint256 heartbeat;
    }

    address public sequencerUptimeFeed;

    uint8 constant WETH_DECIMALS = 18;
    uint8 constant WBTC_DECIMALS = 8; // check on etherscan
    uint8 constant FEED_DECIMALS = 8; // check on etherscan
    uint256 constant FEED_HEARTBEAT = 3600;

    int256 public constant ETH_USD_PRICE = 3000e8;
    int256 public constant BTC_USD_PRICE = 50000e8;

    string[] public tokenNames = ["weth", "wbtc"];
    mapping(string tokenName => NetworkConfig config) public activeNetworkConfig;

    constructor() {
        if (block.chainid == 10) {
            // Optimism Mainnet
            getOpMainnetConfig();
        } else if (block.chainid == 11155111) {
            // Sepolia Testnet
            getEthSepoliaConfig();
        } else {
            // Anvil localnet
            // block.chainid == 31337
            getOrCreateAnvilConfig();
        }
    }

    function getTokenNames() external view returns (string[] memory) {
        return tokenNames;
    }

    function getActiveSequencerUptimeFeed() external view returns (address) {
        return sequencerUptimeFeed;
    }

    function getActiveNetworkConfig(string memory tokenName) external view returns (address, address, uint8, uint256) {
        return (
            activeNetworkConfig[tokenName].tokenAddress,
            activeNetworkConfig[tokenName].priceFeed,
            activeNetworkConfig[tokenName].decimals,
            activeNetworkConfig[tokenName].heartbeat
        );
    }

    function getEthMainnetConfig() public {}

    function getEthSepoliaConfig() public {
        sequencerUptimeFeed = address(0);
        activeNetworkConfig["weth"] = NetworkConfig({
            tokenAddress: 0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa,
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            decimals: WETH_DECIMALS,
            heartbeat: 3600
        });
        activeNetworkConfig["wbtc"] = NetworkConfig({
            tokenAddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            priceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            decimals: WBTC_DECIMALS,
            heartbeat: 3600
        });
    }

    function getOpMainnetConfig() public {
        sequencerUptimeFeed = 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389;
        activeNetworkConfig["weth"] = NetworkConfig({
            tokenAddress: 0x4200000000000000000000000000000000000006,
            priceFeed: 0x13e3Ee699D1909E989722E753853AE30b17e08c5,
            decimals: WETH_DECIMALS,
            heartbeat: 1200
        });
        activeNetworkConfig["wbtc"] = NetworkConfig({
            tokenAddress: 0x68f180fcCe6836688e9084f035309E29Bf0A2095,
            priceFeed: 0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593,
            decimals: WBTC_DECIMALS,
            heartbeat: 1200
        });
    }

    function getOrCreateAnvilConfig() public {
        if (activeNetworkConfig["weth"].tokenAddress != address(0)) {
            return;
        }

        // priceFeed and ERC20 instantiation for WETH
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(WETH_DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", WETH_DECIMALS);
        uint8 wethDecimals = wethMock.decimals();

        // priceFeed and ERC20 instantiation for WBTC
        MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(WBTC_DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", WBTC_DECIMALS);
        uint8 wbtcDecimals = wethMock.decimals();

        sequencerUptimeFeed = address(0);
        activeNetworkConfig["weth"] = NetworkConfig({
            tokenAddress: address(wethMock),
            priceFeed: address(wethPriceFeed),
            decimals: wethDecimals,
            heartbeat: FEED_HEARTBEAT
        });
        activeNetworkConfig["wbtc"] = NetworkConfig({
            tokenAddress: address(wbtcMock),
            priceFeed: address(wbtcPriceFeed),
            decimals: wbtcDecimals,
            heartbeat: FEED_HEARTBEAT
        });
    }
}
