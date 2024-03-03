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
    }

    uint8 constant WETH_DECIMALS = 18;
    uint8 constant WBTC_DECIMALS = 8; // check on etherscan
    uint8 constant FEED_DECIMALS = 8; // check on etherscan

    int256 public constant ETH_USD_PRICE = 3000e8;
    int256 public constant BTC_USD_PRICE = 50000e8;

    string[] public tokenNames = ["weth", "wbtc"];
    mapping(string tokenName => NetworkConfig config) public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            getEthSepoliaConfig();
        } else {
            /* block.chainid == 31337 */
            getOrCreateAnvilConfig();
        }
    }

    function getTokenNames() external view returns (string[] memory) {
        return tokenNames;
    }

    function getActiveNetworkConfig(string memory tokenName) external view returns (address, address, uint8) {
        return (
            activeNetworkConfig[tokenName].tokenAddress,
            activeNetworkConfig[tokenName].priceFeed,
            activeNetworkConfig[tokenName].decimals
        );
    }

    function getEthSepoliaConfig() public {
        activeNetworkConfig["weth"] = NetworkConfig({
            tokenAddress: 0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa,
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            decimals: WETH_DECIMALS
        });
        activeNetworkConfig["wbtc"] = NetworkConfig({
            tokenAddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            priceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            decimals: WBTC_DECIMALS
        });
    }

    function getEthMainnetConfig() public {}

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

        activeNetworkConfig["weth"] =
            NetworkConfig({tokenAddress: address(wethMock), priceFeed: address(wethPriceFeed), decimals: wethDecimals});
        activeNetworkConfig["wbtc"] =
            NetworkConfig({tokenAddress: address(wbtcMock), priceFeed: address(wbtcPriceFeed), decimals: wbtcDecimals});
    }
}
