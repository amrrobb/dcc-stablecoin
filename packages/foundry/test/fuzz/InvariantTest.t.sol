// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDCCScript} from "../../script/DeployDCC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DCCEngine} from "../../contracts/DCCEngine.sol";
import {DCCStablecoin} from "../../contracts/DCCStablecoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDCCScript deployer;
    DCCEngine dccEngine;
    DCCStablecoin dccStablecoin;
    HelperConfig config;
    NetworkConfig wethConfig;
    NetworkConfig wbtcConfig;

    struct NetworkConfig {
        address tokenAddress;
        address priceFeed;
        uint8 decimals;
    }

    function setUp() public {
        deployer = new DeployDCCScript();
        (dccEngine, dccStablecoin, config,) = deployer.run();

        address tokenAddr;
        address priceFeed;
        uint8 dec; // decimals

        // Setup config and mint weth
        (tokenAddr, priceFeed, dec) = config.getActiveNetworkConfig("weth");
        wethConfig = NetworkConfig(tokenAddr, priceFeed, dec);

        // Setup config and mint wbtc
        (tokenAddr, priceFeed, dec) = config.getActiveNetworkConfig("wbtc");
        wbtcConfig = NetworkConfig(tokenAddr, priceFeed, dec);

        targetContract(address(dccEngine));
    }

    function invariant_TotalDepositedValueShouldBeGreaterThanTotalSupply() public {
        // compare all collateral in the protocol with all DCC tokens
        uint256 dccTotalSupply = dccStablecoin.totalSupply();
        uint256 wethTotalDeposited = IERC20(wethConfig.tokenAddress).balanceOf(address(dccEngine));
        uint256 wbtcTotalDeposited = IERC20(wbtcConfig.tokenAddress).balanceOf(address(dccEngine));

        uint256 wethValue = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, wethTotalDeposited);
        uint256 wbtcValue = dccEngine.getUsdValueFromTokenAmount(wbtcConfig.tokenAddress, wbtcTotalDeposited);
        uint256 totalValue = wethValue + wbtcValue;

        assertGe(totalValue, dccTotalSupply);
    }
}
