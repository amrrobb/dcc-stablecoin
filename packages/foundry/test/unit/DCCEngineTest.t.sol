// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDCCScript} from "../../script/DeployDCC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DCCEngine} from "../../contracts/DCCEngine.sol";
import {DCCStablecoin} from "../../contracts/DCCStablecoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract DCCEngineTest is Test {
    DeployDCCScript deployer;
    DCCEngine dccEngine;
    DCCStablecoin dccStablecoin;
    HelperConfig config;
    address sequencerUptimeFeed;
    uint256 deployerKey;
    NetworkConfig wethConfig;
    NetworkConfig wbtcConfig;

    struct NetworkConfig {
        address tokenAddress;
        address priceFeed;
        uint8 decimals;
        uint256 heartbeat;
    }

    // Constructor
    address[] public tokenAddresses;
    DCCEngine.CollateralInformation[] public collateralInformations;

    // User
    address user = makeAddr("user");
    uint256 amountCollateralWeth = 10 ether; // WERH use 18 decimals
    uint256 amountCollateralWbtc = 10e8; // WBTC use 8 decimals
    uint256 amountToMint = 100 ether;

    // Liquidation
    address liquidator = makeAddr("liquidator");
    uint256 amountCollateralToCoverWeth = 20 ether;
    uint256 amountCollateralToCoverWbtc = 20e8;
    uint256 amountDebtToCover = 10 ether;

    // Constant variables
    uint256 constant WETH_PRICE_NO_PRECISION = 3000;
    uint256 constant WBTC_PRICE_NO_PRECISION = 50000;

    uint256 constant DCC_PRECISION = 1e18;
    uint256 constant MIN_HEALTH_FACTOR = 1e18;
    uint256 constant MAX_HEALTH_FACTOR = type(uint256).max;

    uint256 constant WETH_STARTING_BALANCE = 100 ether; // WETH use 18 decimals
    uint256 constant WBTC_STARTING_BALANCE = 100e8; // WBTC use 8 decimals

    uint256 constant LIQUIDATION_BONUS = 10; // Assets will 10% discount when liquidating
    uint256 constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized
    uint256 constant LIQUIDATION_PRECISION = 100;

    // Events
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed collateralToken, uint256 amount
    );

    /*//////////////////////////////////////////////////////
                           Set Up      
    //////////////////////////////////////////////////////*/

    function setUp() public {
        deployer = new DeployDCCScript();
        (dccEngine, dccStablecoin, config, deployerKey) = deployer.run();
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

    /*//////////////////////////////////////////////////////
                      Constructor Tests      
    //////////////////////////////////////////////////////*/

    function testRevertIfTokenAddressesAndPriceFeedAddressesAmountsDontMatch() public {
        // 2 tokenAddresses
        tokenAddresses.push(wethConfig.tokenAddress);
        tokenAddresses.push(wbtcConfig.tokenAddress);

        // 1 collateral informations
        collateralInformations.push(
            DCCEngine.CollateralInformation(wethConfig.priceFeed, wethConfig.decimals, wethConfig.heartbeat)
        );

        vm.expectRevert(DCCEngine.DCCEngine__TokenAddressesAndCollateralInformationsAmountDontMatch.selector);
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

    /*//////////////////////////////////////////////////////
                          Price Tests      
    //////////////////////////////////////////////////////*/

    function testWethToUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * $3000 / ETH
        // 45_000__000_00000_00000_00000
        uint256 expectedUsd = WETH_PRICE_NO_PRECISION * ethAmount;
        uint256 actualUsd = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testWbtcToUsdValue() public {
        uint256 btcAmount = 10e8; // 8 decimals
        // 10e8 * $50_000 BTC / USD * 1e10
        // 500_000__000_00000_00000_00000
        uint256 expectedUsd = WBTC_PRICE_NO_PRECISION * btcAmount * 1e10; // add additional 10 decimals
        uint256 actualUsd = dccEngine.getUsdValueFromTokenAmount(wbtcConfig.tokenAddress, btcAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testUsdToWeth() public {
        uint256 expectedEth = 0.05 ether;
        // 15e18 * $3000 / ETH
        uint256 usdValue = WETH_PRICE_NO_PRECISION * expectedEth;
        uint256 actualEth = dccEngine.getTokenAmountFromUsdValue(wethConfig.tokenAddress, usdValue);
        assertEq(expectedEth, actualEth);
    }

    function testUsdToWbtc() public {
        uint256 expectedBtc = 1e8; // 8 decimals
        // 1e8 * $50_000 BTC / USD * 1e10
        uint256 usdValue = WBTC_PRICE_NO_PRECISION * expectedBtc * 1e10; // add additional 10 decimals
        uint256 actualBtc = dccEngine.getTokenAmountFromUsdValue(wbtcConfig.tokenAddress, usdValue);
        assertEq(expectedBtc, actualBtc);
    }

    /*//////////////////////////////////////////////////////
                    depositCollateral Tests  
    //////////////////////////////////////////////////////*/

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.depositCollateral(wethConfig.tokenAddress, 0);
        vm.stopPrank();
    }

    function testRevertIfDepoistUnallowedCollateralToken() public {
        ERC20Mock newToken = new ERC20Mock("Rand", "Rand", 18);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__NotAllowedToken.selector, address(newToken)));
        dccEngine.depositCollateral(address(newToken), 1e18);
        vm.stopPrank();
    }

    function testReverDepositUnapprovedCollateralToken() public {
        vm.startPrank(user);
        // revert from ERC20 ERC20InsufficientAllowance
        vm.expectRevert();
        dccEngine.depositCollateral(wethConfig.tokenAddress, amountCollateralWeth);
        vm.stopPrank();
    }

    function testRevertIfFailedTransferFrom() public {
        // Mock call for ERC20 transferFrom fails
        vm.mockCall(
            address(wethConfig.tokenAddress),
            abi.encodeWithSelector(IERC20(wethConfig.tokenAddress).transferFrom.selector),
            abi.encode(false)
        );

        vm.startPrank(user);
        ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), WETH_STARTING_BALANCE);
        vm.expectRevert(
            abi.encodeWithSelector(DCCEngine.DCCEngine__TransferFailed.selector, address(wethConfig.tokenAddress))
        );
        dccEngine.depositCollateral(wethConfig.tokenAddress, amountCollateralWeth);
        vm.stopPrank();
    }

    function testDepositCollateralWithEmittedEvent() public {
        vm.startPrank(user);
        ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), WETH_STARTING_BALANCE);

        vm.expectEmit(true, true, true, true, address(dccEngine));
        emit CollateralDeposited(user, wethConfig.tokenAddress, amountCollateralWeth);
        dccEngine.depositCollateral(wethConfig.tokenAddress, amountCollateralWeth);
        vm.stopPrank();

        uint256 balance = dccStablecoin.balanceOf(user);
        assertEq(balance, 0);
    }

    modifier depositedCollateral(uint8 index) {
        vm.startPrank(user);

        bool runWeth = index == 0 || index == 1;
        bool runWbtc = index == 0 || index == 2;

        if (runWeth) {
            ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), WETH_STARTING_BALANCE);
            dccEngine.depositCollateral(wethConfig.tokenAddress, amountCollateralWeth);
        }
        if (runWbtc) {
            ERC20Mock(wbtcConfig.tokenAddress).approve(address(dccEngine), WBTC_STARTING_BALANCE);
            dccEngine.depositCollateral(wbtcConfig.tokenAddress, amountCollateralWbtc);
        }
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndGetAccountInformation() public depositedCollateral(1) {
        (uint256 totalDccMinted, uint256 collateralValueInUsd) = dccEngine.getAccountInformation(user);

        uint256 expectedUsdValue = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, amountCollateralWeth);
        assertEq(totalDccMinted, 0);
        assertEq(collateralValueInUsd, expectedUsdValue);
    }

    /*//////////////////////////////////////////////////////
                          mintDcc Tests      
    //////////////////////////////////////////////////////*/

    function testRevertIfMintAmountIsZero() public depositedCollateral(1) {
        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.mintDcc(0);
        vm.stopPrank();
    }

    function testRevertIfBrokenHealthFactorOnMintDcc() public depositedCollateral(1) {
        (, uint256 collateralValueInUsd) = dccEngine.getAccountInformation(user);
        uint256 expectedHealthFactor = dccEngine.calculateHealthFactor(collateralValueInUsd, collateralValueInUsd);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__BrokenHealthFactor.selector, expectedHealthFactor));
        dccEngine.mintDcc(collateralValueInUsd);
        vm.stopPrank();
    }

    function testRevertIfmintDccFailed() public depositedCollateral(1) {
        // Mock call for DCCStablecoin mint fails
        vm.mockCall(address(dccStablecoin), abi.encodeWithSelector(dccStablecoin.mint.selector), abi.encode(false));

        // Need to overcollateralized
        (, uint256 collateralValueInUsd) = dccEngine.getAccountInformation(user);
        uint256 dccMinted = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;

        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__MintFailed.selector);
        dccEngine.mintDcc(dccMinted);
        vm.stopPrank();
    }

    function testmintDcc() public depositedCollateral(1) {
        // Need to overcollateralized
        (, uint256 collateralValueInUsd) = dccEngine.getAccountInformation(user);
        uint256 expectedDCCMinted = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;

        vm.startPrank(user);
        dccEngine.mintDcc(expectedDCCMinted);
        (uint256 actualDCCMinted,) = dccEngine.getAccountInformation(user);
        vm.stopPrank();

        assertEq(actualDCCMinted, expectedDCCMinted);
    }

    /*//////////////////////////////////////////////////////
                depositCollateralAndMint Tssts  
    //////////////////////////////////////////////////////*/

    function testRevertIfBrokenHealthFactorOnDepositCollateralAndMintDcc() public {
        MockV3Aggregator priceFeed = MockV3Aggregator(wethConfig.priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        amountToMint = (uint256(price) * amountCollateralWeth) / (10 ** priceFeed.decimals());
        uint256 expectedHealthFactor = dccEngine.calculateHealthFactor(
            amountToMint, dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, amountCollateralWeth)
        );

        vm.startPrank(user);
        ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), amountCollateralWeth);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__BrokenHealthFactor.selector, expectedHealthFactor));
        dccEngine.depositCollateralAndMintDcc(wethConfig.tokenAddress, amountCollateralWeth, amountToMint);
        vm.stopPrank();
    }

    function depositedCollateralAndMintedDccHelper(uint8 index) public {
        bool runWeth = index == 0 || index == 1;
        bool runWbtc = index == 0 || index == 2;

        vm.startPrank(user);
        if (runWeth) {
            ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), WETH_STARTING_BALANCE);
            dccEngine.depositCollateralAndMintDcc(wethConfig.tokenAddress, amountCollateralWeth, amountToMint);
        }
        if (runWbtc) {
            ERC20Mock(wbtcConfig.tokenAddress).approve(address(dccEngine), WBTC_STARTING_BALANCE);
            dccEngine.depositCollateralAndMintDcc(wbtcConfig.tokenAddress, amountCollateralWbtc, amountToMint);
        }
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDcc(uint8 index) {
        depositedCollateralAndMintedDccHelper(index);
        _;
    }

    function testDepositCollateralAndMintDcc() public depositedCollateralAndMintedDcc(1) {
        uint256 balance = dccStablecoin.balanceOf(user);
        assertEq(balance, amountToMint);
    }

    /*//////////////////////////////////////////////////////
                          burnDcc Tests      
    //////////////////////////////////////////////////////*/

    function testRevertIfBurnAmountIsZero() public depositedCollateralAndMintedDcc(1) {
        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.burnDcc(0);
        vm.stopPrank();
    }

    function testRevertIfBurnDccFailed() public depositedCollateralAndMintedDcc(1) {
        // Mock call for DCCStablecoin transferFrom fails
        vm.mockCall(
            address(dccStablecoin), abi.encodeWithSelector(dccStablecoin.transferFrom.selector), abi.encode(false)
        );

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__TransferFailed.selector, address(dccStablecoin)));
        dccEngine.burnDcc(amountToMint);
        vm.stopPrank();
    }

    function testBurnDcc() public depositedCollateralAndMintedDcc(1) {
        vm.startPrank(user);
        dccStablecoin.approve(address(dccEngine), amountToMint);
        dccEngine.burnDcc(amountToMint);
        vm.stopPrank();

        uint256 balance = dccStablecoin.balanceOf(user);
        assertEq(balance, 0);
    }

    function testCannotBurnDccMoreThanUserHas() public {
        vm.startPrank(user);
        vm.expectRevert();
        dccEngine.burnDcc(1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////
                    redeemCollateral Tests  
    //////////////////////////////////////////////////////*/

    function testRevertIfRedeemAmountIsZero() public depositedCollateral(1) {
        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.redeemCollateral(wethConfig.tokenAddress, 0);
        vm.stopPrank();
    }

    function testRevertIfRedeemIsNotAllowedToken() public depositedCollateral(1) {
        address randomAddr = vm.addr(1);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__NotAllowedToken.selector, randomAddr));
        dccEngine.redeemCollateral(randomAddr, amountCollateralWeth);
        vm.stopPrank();
    }

    function testRevertIfRedeemCollateralFailed() public depositedCollateral(1) {
        // Mock call for DCCStablecoin transferFrom fails
        vm.mockCall(
            address(wethConfig.tokenAddress),
            abi.encodeWithSelector(IERC20(wethConfig.tokenAddress).transfer.selector),
            abi.encode(false)
        );

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(DCCEngine.DCCEngine__TransferFailed.selector, address(wethConfig.tokenAddress))
        );
        dccEngine.redeemCollateral(wethConfig.tokenAddress, amountCollateralWeth);
        vm.stopPrank();
    }

    function testRevertIfBrokenHealthFactorOnRedeemCollateral() public depositedCollateralAndMintedDcc(1) {
        (uint256 totalDccMinted,) = dccEngine.getAccountInformation(user);
        uint256 expectedHealthFactor = dccEngine.calculateHealthFactor(totalDccMinted, 0);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__BrokenHealthFactor.selector, expectedHealthFactor));
        dccEngine.redeemCollateral(wethConfig.tokenAddress, amountCollateralWeth);
        vm.stopPrank();
    }

    function testRedeemCollateralWithEmittedEvent() public depositedCollateral(1) {
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true, address(dccEngine));
        emit CollateralRedeemed(user, user, wethConfig.tokenAddress, amountCollateralWeth);
        dccEngine.redeemCollateral(wethConfig.tokenAddress, amountCollateralWeth);
        vm.stopPrank();

        uint256 balance = ERC20Mock(wethConfig.tokenAddress).balanceOf(user);
        assertEq(balance, WETH_STARTING_BALANCE);
    }

    /*//////////////////////////////////////////////////////
                 redeemCollateralForDcc Tssts  
    //////////////////////////////////////////////////////*/

    function testRevertIfRedeemAmountIsZeroOnRedeemCollateralForDcc() public depositedCollateralAndMintedDcc(1) {
        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.redeemCollateralForDcc(wethConfig.tokenAddress, 0, amountToMint);
        vm.stopPrank();
    }

    function testRevertIfBurnAmountIsZeroOnRedeemCollateralForDcc() public depositedCollateralAndMintedDcc(1) {
        vm.startPrank(user);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.redeemCollateralForDcc(wethConfig.tokenAddress, amountCollateralWeth, 0);
        vm.stopPrank();
    }

    function testRevertIfBrokenHealthFactorOnRedeemCollateralForDcc() public depositedCollateralAndMintedDcc(1) {
        (uint256 totalDccMinted,) = dccEngine.getAccountInformation(user);
        uint256 expectedHealthFactor = dccEngine.calculateHealthFactor(totalDccMinted, 0);

        vm.startPrank(user);
        dccStablecoin.approve(address(dccEngine), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DCCEngine.DCCEngine__BrokenHealthFactor.selector, expectedHealthFactor));
        // error because undercollateralized
        dccEngine.redeemCollateralForDcc(wethConfig.tokenAddress, amountCollateralWeth, 1);
        vm.stopPrank();
    }

    function testRedeemCollateralForDcc() public depositedCollateralAndMintedDcc(1) {
        vm.startPrank(user);
        dccStablecoin.approve(address(dccEngine), amountToMint);
        dccEngine.redeemCollateralForDcc(wethConfig.tokenAddress, amountCollateralWeth, amountToMint);
        vm.stopPrank();

        uint256 balanceWeth = ERC20Mock(wethConfig.tokenAddress).balanceOf(user);
        uint256 balanceDcc = dccStablecoin.balanceOf(user);

        assertEq(balanceWeth, WETH_STARTING_BALANCE);
        assertEq(balanceDcc, 0);
    }

    /*//////////////////////////////////////////////////////
                      healthFactor Tests      
    //////////////////////////////////////////////////////*/

    function testGetUserHealthFactor() public depositedCollateralAndMintedDcc(1) {
        uint256 collateralValueInUsd =
            dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, amountCollateralWeth);
        // 10 * 3000e18 = 30_000e18 (total weth in usd)
        uint256 expectedHealthFactor = dccEngine.calculateHealthFactor(amountToMint, collateralValueInUsd);
        // (30_000e18 (total weth in usd) * 50% (liquidation percentage) * 1e18 (dcc precision)) / 100e18 (total dcc minted) = 150e18

        uint256 actualHealthFactor = dccEngine.getHealthFactor(user);
        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanBelowOne() public depositedCollateralAndMintedDcc(1) {
        int256 ethUsdUpdatedPrice = 10e8; // 1 ETH = $10
        MockV3Aggregator(wethConfig.priceFeed).updateAnswer(ethUsdUpdatedPrice);
        /**
         *     collateral => 10 * 10e18 = 100e18 (total weth in usd)
         *     healtfactor => (100e18 (total weth in usd) * 50% (liquidation percentage) * 1e18 (dcc precision)) / 100e18 (total dcc minted) = 0.5e18
         */
        uint256 actualHealthFactor = dccEngine.getHealthFactor(user);
        assertLt(actualHealthFactor, MIN_HEALTH_FACTOR);
    }

    /*//////////////////////////////////////////////////////
                       Liquidation Tests      
    //////////////////////////////////////////////////////*/

    function testRevertIfDebtAmountIsZero() public {
        vm.startPrank(liquidator);
        vm.expectRevert(DCCEngine.DCCEngine__ShouldMoreThanZero.selector);
        dccEngine.liquidate(user, wethConfig.tokenAddress, 0);
        vm.stopPrank();
    }

    function testRevertIfGoodHealthFactorWhenLiquidate() public depositedCollateralAndMintedDcc(1) {
        vm.startPrank(liquidator);
        vm.expectRevert(DCCEngine.DCCEngine__GoodHealthFactor.selector);
        dccEngine.liquidate(user, wethConfig.tokenAddress, amountToMint);
        vm.stopPrank();
    }

    function testRevertIfExcessADebtAmountToCoverWhenLiquidate() public depositedCollateralAndMintedDcc(1) {
        int256 ethUsdUpdatedPrice = 10e8; // 1 ETH = $10
        MockV3Aggregator(wethConfig.priceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.startPrank(liquidator);
        vm.expectRevert(DCCEngine.DCCEngine__ExcessDebtAmountToCover.selector);
        dccEngine.liquidate(user, wethConfig.tokenAddress, amountToMint + 1);
        vm.stopPrank();
    }

    function testRevertNotImprovedHealthFactor() public depositedCollateralAndMintedDcc(1) {
        // Arrange liquidator
        ERC20Mock(wethConfig.tokenAddress).mint(liquidator, amountCollateralToCoverWeth);

        vm.startPrank(liquidator);
        ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), amountCollateralToCoverWeth);
        dccEngine.depositCollateralAndMintDcc(wethConfig.tokenAddress, amountCollateralToCoverWeth, amountToMint);

        // Price Modification
        int256 ethUsdUpdatedPrice = 10e8; // 1 ETH = $10
        dccStablecoin.approve(address(dccEngine), amountDebtToCover);
        MockV3Aggregator(wethConfig.priceFeed).updateAnswer(ethUsdUpdatedPrice);

        // Assert
        // Liquidation not improved the health factor of user that will be liqudated
        vm.expectRevert(DCCEngine.DCCEngine__NotImprovedHealthFactor.selector);
        dccEngine.liquidate(user, wethConfig.tokenAddress, amountDebtToCover);
        vm.stopPrank();
    }

    function liquidatedHelper() public {
        amountCollateralToCoverWeth = 1000 ether;

        vm.startPrank(liquidator);
        int256 ethUsdUpdatedPrice = 15e8; // 1 ETH = $15
        MockV3Aggregator(wethConfig.priceFeed).updateAnswer(ethUsdUpdatedPrice);
        ERC20Mock(wethConfig.tokenAddress).mint(liquidator, amountCollateralToCoverWeth);
        ERC20Mock(wethConfig.tokenAddress).approve(address(dccEngine), amountCollateralToCoverWeth);

        dccEngine.depositCollateralAndMintDcc(wethConfig.tokenAddress, amountCollateralToCoverWeth, amountToMint);
        dccStablecoin.approve(address(dccEngine), amountToMint);
        dccEngine.liquidate(user, wethConfig.tokenAddress, amountToMint);

        vm.stopPrank();
    }

    modifier liquidated() {
        depositedCollateralAndMintedDccHelper(1);
        liquidatedHelper();
        _;
    }

    function testUserStillHasSomeCollaterlAfterLiquidation() public liquidated {
        uint256 liquidatedAmount = dccEngine.getTokenAmountFromUsdValue(wethConfig.tokenAddress, amountToMint)
            + (
                dccEngine.getTokenAmountFromUsdValue(wethConfig.tokenAddress, amountToMint)
                    / dccEngine.getLiquidationBonus()
            );
        uint256 liquidatedInUsd = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, liquidatedAmount);
        uint256 expectedCollateralInUsd =
            dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, amountCollateralWeth) - liquidatedInUsd;
        (, uint256 actualCollateralInUsd) = dccEngine.getAccountInformation(user);
        assertEq(expectedCollateralInUsd, actualCollateralInUsd);
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(wethConfig.tokenAddress).balanceOf(liquidator);
        uint256 expectedWeth = dccEngine.getTokenAmountFromUsdValue(wethConfig.tokenAddress, amountToMint)
            + (
                dccEngine.getTokenAmountFromUsdValue(wethConfig.tokenAddress, amountToMint)
                    / dccEngine.getLiquidationBonus()
            );
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDccMinted,) = dccEngine.getAccountInformation(liquidator);
        assertEq(liquidatorDccMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDccMinted,) = dccEngine.getAccountInformation(user);
        assertEq(userDccMinted, 0);
    }

    /*//////////////////////////////////////////////////////
                  Pure & View Functions Tests      
    //////////////////////////////////////////////////////*/

    function testCalculateHealthFactorOnZeroDccMinted() public {
        uint256 healthFactor = dccEngine.calculateHealthFactor(0, 1e18);
        assertEq(healthFactor, MAX_HEALTH_FACTOR);
    }

    function testCalculateHealthFactorOnDccAlreadyMinted(uint256 totalDccMinted, uint256 collateralValueInUsd) public {
        totalDccMinted = bound(totalDccMinted, 1, 100e18);
        collateralValueInUsd = bound(collateralValueInUsd, 1, 100e18);

        uint256 actualHealthFactor = dccEngine.calculateHealthFactor(totalDccMinted, collateralValueInUsd);

        uint256 collateralAdjustedByThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        uint256 expectedHealthFactor = collateralAdjustedByThreshold * MIN_HEALTH_FACTOR / totalDccMinted;

        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testGetLiquidationBonus() public {
        assertEq(dccEngine.getLiquidationBonus(), LIQUIDATION_BONUS);
    }

    function testGetLiquidationThreshold() public {
        assertEq(dccEngine.getLiquidationThreshold(), LIQUIDATION_THRESHOLD);
    }

    function testGetLiquidationPrecision() public {
        assertEq(dccEngine.getLiquidationPrecision(), LIQUIDATION_PRECISION);
    }

    function testGetMinHealthFactor() public {
        assertEq(dccEngine.getMinHealthFactor(), MIN_HEALTH_FACTOR);
    }

    function testGetMaxHealthFactor() public {
        assertEq(dccEngine.getMaxHealthFactor(), MAX_HEALTH_FACTOR);
    }

    function testGetDccPrecision() public {
        assertEq(dccEngine.getDccPrecision(), DCC_PRECISION);
    }

    function testGetDccAddress() public {
        assertEq(dccEngine.getDccAddress(), address(dccStablecoin));
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dccEngine.getCollateralTokens();
        assertEq(collateralTokens[0], wethConfig.tokenAddress);
        assertEq(collateralTokens[1], wbtcConfig.tokenAddress);
    }

    function testGetCollateralInformation() public {
        DCCEngine.CollateralInformation memory wethInfo = dccEngine.getCollateralInformation(wethConfig.tokenAddress);
        assertEq(wethInfo.priceFeed, wethConfig.priceFeed);
        assertEq(wethInfo.decimals, wethConfig.decimals);
        assertEq(wethInfo.heartbeat, wethConfig.heartbeat);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral(0) {
        assertEq(dccEngine.getCollateralBalanceOfUser(user, wethConfig.tokenAddress), amountCollateralWeth);
        assertEq(dccEngine.getCollateralBalanceOfUser(user, wbtcConfig.tokenAddress), amountCollateralWbtc);
    }

    function testGetCollateralValueOfUser() public depositedCollateral(0) {
        uint256 valueWeth = dccEngine.getUsdValueFromTokenAmount(wethConfig.tokenAddress, amountCollateralWeth);
        uint256 valueWbtc = dccEngine.getUsdValueFromTokenAmount(wbtcConfig.tokenAddress, amountCollateralWbtc);
        uint256 expectedValue = valueWeth + valueWbtc;
        uint256 actualValue = dccEngine.getCollateralValueOfUser(user);
        assertEq(actualValue, expectedValue);
    }
}
