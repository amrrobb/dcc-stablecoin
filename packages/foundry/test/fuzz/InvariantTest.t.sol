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
import {Handler} from "./Handler.t.sol";
import {console} from "forge-std/console.sol";

/**
 * Invariants
 *  1. collaterral must be greater than equal the DCC total supply
 *  2. getter view function sholud never revert - evergreen invariant
 */

contract InvariantTest is StdInvariant, Test {
    DeployDCCScript deployer;
    DCCEngine dccEngine;
    DCCStablecoin dccStablecoin;
    HelperConfig config;
    NetworkConfig wethConfig;
    NetworkConfig wbtcConfig;
    Handler handler;

    uint256 constant WETH_STARTING_BALANCE = 10 ether; // WETH use 18 decimals
    uint256 constant WBTC_STARTING_BALANCE = 10e8; // WBTC use 8 decimals

    struct NetworkConfig {
        address tokenAddress;
        address priceFeed;
        uint8 decimals;
        uint256 heartbeat;
    }

    function setUp() public {
        deployer = new DeployDCCScript();
        (dccEngine, dccStablecoin, config,) = deployer.run();

        address tokenAddr;
        address priceFeed;
        uint8 dec; // decimals
        uint256 heartbeat;

        // Setup config and mint weth
        (tokenAddr, priceFeed, dec, heartbeat) = config.getActiveNetworkConfig("weth");
        wethConfig = NetworkConfig(tokenAddr, priceFeed, dec, heartbeat);

        // Setup config and mint wbtc
        (tokenAddr, priceFeed, dec, heartbeat) = config.getActiveNetworkConfig("wbtc");
        wbtcConfig = NetworkConfig(tokenAddr, priceFeed, dec, heartbeat);

        handler = new Handler(dccEngine, dccStablecoin);
        targetContract(address(handler));
    }

    function invariant_totalDepositedValueShouldBeGreaterThanTotalSupply() public {
        // compare all collateral in the protocol with all DCC tokens
        uint256 dccTotalSupply = dccStablecoin.totalSupply();
        uint256 wethTotalDeposited = IERC20(wethConfig.tokenAddress).balanceOf(address(dccEngine));
        uint256 wbtcTotalDeposited = IERC20(wbtcConfig.tokenAddress).balanceOf(address(dccEngine));

        uint256 wethValue = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, wethTotalDeposited);
        uint256 wbtcValue = dccEngine.getUsdValueFromTokenAmount(wbtcConfig.tokenAddress, wbtcTotalDeposited);
        uint256 totalValue = wethValue + wbtcValue;

        // console.log("weth value:", wethValue);
        // console.log("wbtch value:", wbtcValue);
        // console.log("total value:", totalValue);

        assertGe(totalValue, dccTotalSupply);
    }

    function invariant_getterShouldNevertRevert() public view {
        //   dccEngine.getAccountInformation(address);
        //   dccEngine.getCollateralBalanceOfUser(address,address);
        // dccEngine.getCollateralInformation(address);
        dccEngine.getCollateralTokens();
        dccEngine.getDccAddress();
        dccEngine.getDccPrecision();
        //   dccEngine.getHealthFactor(address);
        dccEngine.getLiquidationBonus();
        dccEngine.getLiquidationPrecision();
        dccEngine.getLiquidationThreshold();
        dccEngine.getMaxHealthFactor();
        dccEngine.getMinHealthFactor();
        //   dccEngine.getTokenAmountFromUsdValue(address,uint256);
        //   dccEngine.getUsdValueFromTokenAmount(address,uint256);
    }
}
