// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDCCScript} from "../../script/DeployDCC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DCCEngine} from "../../contracts/DCCEngine.sol";
import {DCCStablecoin} from "../../contracts/DCCStablecoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DCCEngineTest is Test {
    DeployDCCScript deployer;
    DCCEngine dccEngine;
    DCCStablecoin dccStablecoin;
    HelperConfig config;
    address sequencerUptimeFeed;

    uint256 deployerKey;

    // ERC20Mock wethMock;
    // ERC20Mock wbtcMock;

    address user = makeAddr("user");

    struct NetworkConfig {
        address tokenAddress;
        address priceFeed;
        uint8 decimals;
        uint256 heartbeat;
    }

    NetworkConfig wethConfig;
    NetworkConfig wbtcConfig;
    uint256 constant WETH_PRICE_NO_PRECISION = 3000;
    uint256 constant WBTC_PRICE_NO_PRECISION = 50000;
    uint256 constant WETH_STARTING_BALANCE = 10 ether; // WETH use 18 decimals
    uint256 constant WBTC_STARTING_BALANCE = 10e8; // WBTC use 8 decimals
    uint256 constant WETH_DEPOSITED = 1 ether; // WBTC use 8 decimals
    uint256 constant WBTC_DEPOSITED = 1e8; // WBTC use 8 decimals

    function setUp() public {
        deployer = new DeployDCCScript();
        (dccEngine, dccStablecoin, config, deployerKey) = deployer.run();
        // order by index: weth, wbtc
        // (
        //     address[] memory collateralTokenAddresses,
        //     address[] memory priceFeedAddresses,
        //     uint8[] memory collateralTokendDecimals,
        //     string[] memory tokenNames
        // ) =
        // deployer.getDeployedParameters();
        sequencerUptimeFeed = config.getActiveSequencerUptimeFeed();

        address tokenAddr;
        address priceFeed;
        uint8 dec;
        uint256 heartbeat;

        // Setup config and mint weth
        (tokenAddr, priceFeed, dec, heartbeat) = config.getActiveNetworkConfig("weth");
        wethConfig = NetworkConfig(tokenAddr, priceFeed, dec, heartbeat);
        ERC20Mock(tokenAddr).mint(user, WETH_STARTING_BALANCE);

        // Setup config and mint wbtc
        (tokenAddr, priceFeed, dec, heartbeat) = config.getActiveNetworkConfig("wbtc");
        wbtcConfig = NetworkConfig(tokenAddr, priceFeed, dec, heartbeat);
        ERC20Mock(tokenAddr).mint(user, WBTC_STARTING_BALANCE);
    }

    // Constructor Tests
    address[] public tokenAddresses;
    // address[] public priceFeeds;
    // uint8[] public tokenDecimals;
    DCCEngine.CollateralInformation[] public collateralInformations;

    function testRevertIfTokenAddressesAndPriceFeedAddressesAmountsDontMatch() public {
        // 2 tokenAddresses
        tokenAddresses.push(wethConfig.tokenAddress);
        tokenAddresses.push(wbtcConfig.tokenAddress);

        // 1 collateral informations
        collateralInformations.push(
            DCCEngine.CollateralInformation(wethConfig.priceFeed, wethConfig.decimals, wethConfig.heartbeat)
        );

        vm.expectRevert(DCCEngine.DCCEngine__TokenAddressesAndCollateralInforamtionsAmountDontMatch.selector);
        new DCCEngine(tokenAddresses, collateralInformations, sequencerUptimeFeed);
    }

    function testSuccessInstantiateDCCEngine() public {
        // 2 tokenAddresses
        tokenAddresses.push(wethConfig.tokenAddress);
        tokenAddresses.push(wbtcConfig.tokenAddress);

        // 2 collateral informations
        collateralInformations.push(
            DCCEngine.CollateralInformation(wethConfig.priceFeed, wethConfig.decimals, wethConfig.heartbeat)
        );
        collateralInformations.push(
            DCCEngine.CollateralInformation(wbtcConfig.priceFeed, wbtcConfig.decimals, wbtcConfig.heartbeat)
        );

        new DCCEngine(tokenAddresses, collateralInformations, sequencerUptimeFeed);
    }

    // Modifiers
    modifier depositedCollateral(uint8 index) {
        vm.startPrank(user);

        bool runWeth = index == 0 || index == 1;
        bool runWbtc = index == 0 || index == 2;

        if (runWeth) {
            ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), WETH_STARTING_BALANCE);
            dccEngine.depositCollateral(wethConfig.tokenAddress, WETH_DEPOSITED);
        }
        if (runWbtc) {
            ERC20Mock(wbtcConfig.tokenAddress).approve(address(dccEngine), WBTC_STARTING_BALANCE);
            dccEngine.depositCollateral(wbtcConfig.tokenAddress, WBTC_DEPOSITED);
        }
        vm.stopPrank();
        _;
    }

    // Function Tests
    function testWethToUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * $3000 / ETH
        uint256 expectedUsd = WETH_PRICE_NO_PRECISION * ethAmount;
        uint256 actualUsd = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testWbtcToUsdValue() public {
        uint256 btcAmount = 10e8;
        // 10e8 * $50_000 / BTC
        uint256 expectedUsd = WBTC_PRICE_NO_PRECISION * btcAmount;
        uint256 actualUsd = dccEngine.getUsdValueFromTokenAmount(wbtcConfig.tokenAddress, btcAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function revertIfCollateralIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.depositCollateral(wethConfig.tokenAddress, 0);
        vm.stopPrank();
    }

    function testUsdToWeth() public {
        uint256 expectedEth = 0.05 ether;
        // 15e18 * $3000 / ETH
        uint256 usdValue = WETH_PRICE_NO_PRECISION * expectedEth;
        uint256 actualEth = dccEngine.getTokenAmountFromUsdValue(wethConfig.tokenAddress, usdValue);
        assertEq(expectedEth, actualEth);
    }

    function testUsdToWbtc() public {
        uint256 expectedBtc = 1e8;
        // 1e8 * $50_000 / BTC
        uint256 usdValue = WBTC_PRICE_NO_PRECISION * expectedBtc;
        uint256 actualBtc = dccEngine.getTokenAmountFromUsdValue(wbtcConfig.tokenAddress, usdValue);
        assertEq(expectedBtc, actualBtc);
    }

    function testRevertUnallowedCollateralToken() public {
        ERC20Mock newToken = new ERC20Mock("Rand", "Rand", 18);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__NotAllowedToken.selector, address(newToken)));
        dccEngine.depositCollateral(address(newToken), 1e18);
        vm.stopPrank();
    }

    function testRevertUnapprovedCollateralToken() public {
        vm.startPrank(user);
        // revert from ERC20 ERC20InsufficientAllowance
        vm.expectRevert();
        dccEngine.depositCollateral(wethConfig.tokenAddress, 1e18);
        vm.stopPrank();
    }

    function testSuccesDepositedCollateralToken() public {
        vm.startPrank(user);
        ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), WETH_STARTING_BALANCE);

        dccEngine.depositCollateral(wethConfig.tokenAddress, 1e18);
        vm.stopPrank();
    }

    function testGetAccountInformation() public depositedCollateral(1) {
        (uint256 totalDccMinted, uint256 collateralValueInUsd) = dccEngine.getAccountInformation(user);

        uint256 expectedUsdValue = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, WETH_DEPOSITED);
        assertEq(totalDccMinted, 0);
        assertEq(collateralValueInUsd, expectedUsdValue);
    }
}
