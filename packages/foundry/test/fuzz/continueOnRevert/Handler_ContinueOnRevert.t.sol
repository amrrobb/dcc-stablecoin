// Commented out for now until revert on fail == false per function customization is implemented

// // SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// import {Test} from "forge-std/Test.sol";
// import {DeployDCCScript} from "../../../script/DeployDCC.s.sol";
// import {HelperConfig} from "../../../script/HelperConfig.s.sol";
// import {DCCEngine} from "../../../contracts/DCCEngine.sol";
// import {DCCStablecoin} from "../../../contracts/DCCStablecoin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
// import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
// import {console} from "forge-std/console.sol";

// contract Handler_ContinueOnRevert is Test {
//     DCCEngine dccEngine;
//     DCCStablecoin dccStablecoin;

//     ERC20Mock wethMock;
//     ERC20Mock wbtcMock;

//     MockV3Aggregator ethUsdPriceFeed;
//     MockV3Aggregator btcUsdPriceFeed;

//     // Ghost Variables
//     uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
//     // uint256 public timeMintIsCalled;
//     mapping(address user => bool isDeposited) public checkCollateralDepositedUsers;
//     address[] public collateralDepositedUsers;

//     constructor(DCCEngine _dccEngine, DCCStablecoin _dccStablecoin) {
//         dccEngine = _dccEngine;
//         dccStablecoin = _dccStablecoin;

//         address[] memory collateralTokens = dccEngine.getCollateralTokens();
//         wethMock = ERC20Mock(collateralTokens[0]);
//         wbtcMock = ERC20Mock(collateralTokens[1]);

//         ethUsdPriceFeed = MockV3Aggregator(dccEngine.getCollateralInformation(collateralTokens[0]).priceFeed);
//         btcUsdPriceFeed = MockV3Aggregator(dccEngine.getCollateralInformation(collateralTokens[1]).priceFeed);
//     }

//     // Functions to Interact with

//     // DCC Engine
//     function mintAndDepositCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
//         collateralAmount = bound(collateralAmount, 0, MAX_DEPOSIT_SIZE);
//         ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
//         collateral.mint(msg.sender, collateralAmount);
//         dccEngine.depositCollateral(address(collateral), collateralAmount);
//     }

//     function redeemCollateral(uint256 collateralSeed, uint256 collateralAmount) public {
//         collateralAmount = bound(collateralAmount, 0, MAX_DEPOSIT_SIZE);
//         ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
//         dccEngine.redeemCollateral(address(collateral), collateralAmount);
//     }

//     function burnDcc(uint256 dccAmount) public {
//         dccAmount = bound(dccAmount, 0, dccStablecoin.balanceOf(msg.sender));
//         dccStablecoin.burn(dccAmount);
//     }

//     function mintDcc(uint256 dccAmount) public {
//         dccAmount = bound(dccAmount, 0, MAX_DEPOSIT_SIZE);
//         dccStablecoin.mint(msg.sender, dccAmount);
//     }

//     function liquidate(uint256 collateralSeed, address userToBeLiquidated, uint256 debtToCover) public {
//         ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
//         dccEngine.liquidate(address(collateral), userToBeLiquidated, debtToCover);
//     }

//     // DCC Stablecoin
//     function transferDcc(uint256 dccAmount, address to) public {
//         dccAmount = bound(dccAmount, 0, dccStablecoin.balanceOf(msg.sender));
//         vm.prank(msg.sender);
//         dccStablecoin.transfer(to, dccAmount);
//     }

//     // Aggregator
//     function updateCollateralPrice(uint256 collateralSeed, uint96 newPrice) public {
//         int256 intNewPrice = int256(uint256(newPrice));
//         if (intNewPrice <= 0) {
//             return;
//         }
//         ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
//         MockV3Aggregator priceFeed = MockV3Aggregator(dccEngine.getCollateralInformation(address(collateral)).priceFeed);
//         priceFeed.updateAnswer(intNewPrice);
//     }

//     // Helper Functions
//     function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
//         if (collateralSeed % 2 == 0) {
//             return wethMock;
//         }
//         return wbtcMock;
//     }

//     function callSummary() external view {
//         console.log("Weth total deposited", wethMock.balanceOf(address(dccEngine)));
//         console.log("Wbtc total deposited", wbtcMock.balanceOf(address(dccEngine)));
//         console.log("Total supply of Dcc", dccStablecoin.totalSupply());
//     }
// }
