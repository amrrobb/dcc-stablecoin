// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DCCStablecoin} from "../../contracts/DCCStablecoin.sol";
// import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DCCStablecoinTest is Test {
    DCCStablecoin dccStablecoin;

    address owner = makeAddr("owner");

    function setUp() public {
        dccStablecoin = new DCCStablecoin(owner);
    }

    function testReverOnMintToZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__NotZeroAddress.selector);
        dccStablecoin.mint(address(0), 100);
        vm.stopPrank();
    }

    function testMintAmountMustGreaterThanZero() public {
        vm.startPrank(owner);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__AmountMustBeGreaterThanZero.selector);
        dccStablecoin.mint(address(this), 0);
        vm.stopPrank();
    }

    function tesSuccesstMintDCC() public {
        uint256 amountToMint = 100;

        vm.startPrank(owner);
        dccStablecoin.mint(address(this), amountToMint);
        vm.stopPrank();

        uint256 balance = dccStablecoin.balanceOf(address(this));
        assertEq(balance, amountToMint);
    }

    function testBurnAmountMustGreaterThanZero() public {
        vm.startPrank(owner);
        dccStablecoin.mint(address(this), 100);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__AmountMustBeGreaterThanZero.selector);
        dccStablecoin.burn(0);
        vm.stopPrank();
    }

    function testBurnAmountCannotExceedTheBalance() public {
        vm.startPrank(owner);
        dccStablecoin.mint(address(this), 100);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__BurnAmountExceedsBalance.selector);
        dccStablecoin.burn(101);
        vm.stopPrank();
    }

    function tesSuccesstBurnDCC() public {
        uint256 amountToMint = 100;
        uint256 amountToBurn = 50;

        vm.startPrank(owner);
        dccStablecoin.mint(address(this), amountToMint);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__BurnAmountExceedsBalance.selector);
        dccStablecoin.burn(amountToBurn);
        vm.stopPrank();

        uint256 balance = dccStablecoin.balanceOf(address(this));
        assertEq(balance, amountToMint - amountToBurn);
    }
}
