// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDCCScript} from "../../script/DeployDCC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DCCEngine} from "../../contracts/DCCEngine.sol";
import {DCCStablecoin} from "../../contracts/DCCStablecoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract Handler is Test {
    DCCEngine dccEngine;
    DCCStablecoin dccStablecoin;

    ERC20Mock wethMock;
    ERC20Mock wbtcMock;

    MockV3Aggregator ethUsdPriceFeed;
    MockV3Aggregator btcUsdPriceFeed;

    // Ghost Variables
    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    // uint256 public timeMintIsCalled;
    mapping(address user => bool isDeposited) public checkCollateralDepositedUsers;
    address[] public collateralDepositedUsers;

    constructor(DCCEngine _dccEngine, DCCStablecoin _dccStablecoin) {
        dccEngine = _dccEngine;
        dccStablecoin = _dccStablecoin;

        address[] memory collateralTokens = dccEngine.getCollateralTokens();
        wethMock = ERC20Mock(collateralTokens[0]);
        wbtcMock = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dccEngine.getCollateralInformation(collateralTokens[0]).priceFeed);
        btcUsdPriceFeed = MockV3Aggregator(dccEngine.getCollateralInformation(collateralTokens[1]).priceFeed);
    }

    function mintAndDepositCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        collateralAmount = bound(collateralAmount, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        collateral.mint(msg.sender, collateralAmount);
        vm.startPrank(msg.sender);
        collateral.approve(address(dccEngine), collateralAmount);
        dccEngine.depositCollateral(address(collateral), collateralAmount);
        vm.stopPrank();

        if (checkCollateralDepositedUsers[msg.sender] == false) {
            checkCollateralDepositedUsers[msg.sender] == true;
            collateralDepositedUsers.push(msg.sender);
        }
    }

    function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralAmount = dccEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        collateralAmount = bound(collateralAmount, 0, maxCollateralAmount);
        vm.startPrank(msg.sender);
        if (collateralAmount == 0) {
            return;
        }
        dccEngine.redeemCollateral(address(collateral), collateralAmount);
        vm.stopPrank();
    }

    // Only DCC Engine is allowed to mint DCC
    // Uncomment if you already commented updateCollateralPrice
    // function mintDcc(uint256 addressSeed, uint256 amount) public {
    //     if (collateralDepositedUsers.length == 0) {
    //         return;
    //     }
    //     address sender = _getSender(addressSeed);
    //     (uint256 totalDccMinted, uint256 collateralValueInUsd) = dccEngine.getAccountInformation(sender);

    //     int256 maxDCCToMint = (int256(collateralValueInUsd) / 2) - int256(totalDccMinted);
    //     if (maxDCCToMint <= 0) {
    //         return;
    //     }
    //     amount = bound(amount, 0, uint256(maxDCCToMint));
    //     if (amount == 0) {
    //         return;
    //     }

    //     vm.startPrank(sender);
    //     dccEngine.mintDcc(amount);
    //     vm.stopPrank();
    // }

    function burnDcc(uint256 amount) public {
        amount = bound(amount, 0, dccStablecoin.balanceOf(msg.sender));
        if (amount == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dccStablecoin.approve(address(dccEngine), amount);
        dccEngine.burnDcc(amount);
        vm.stopPrank();
    }

    function updateCollateralPrice(uint256 collateralSeed, uint96 newPrice) public {
        int256 intNewPrice = int256(uint256(newPrice));
        if (intNewPrice <= 0) {
            return;
        }
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(dccEngine.getCollateralInformation(address(collateral)).priceFeed);
        priceFeed.updateAnswer(intNewPrice);
    }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return wethMock;
        }
        return wbtcMock;
    }

    function _getSender(uint256 addressSeed) private view returns (address) {
        return collateralDepositedUsers[addressSeed % collateralDepositedUsers.length];
    }

    function callSummary() external view {
        console.log("Weth total deposited", wethMock.balanceOf(address(dccEngine)));
        console.log("Wbtc total deposited", wbtcMock.balanceOf(address(dccEngine)));
        console.log("Total supply of DSC", dccStablecoin.totalSupply());
    }
}
