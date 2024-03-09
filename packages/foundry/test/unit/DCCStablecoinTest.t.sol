// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DCCStablecoin} from "../../contracts/DCCStablecoin.sol";

contract DCCStablecoinTest is Test {
    DCCStablecoin dccStablecoin;

    address owner = makeAddr("owner");
    uint256 amountToMint = 100 ether;
    uint256 amountToBurn = 50 ether;

    function setUp() public {
        dccStablecoin = new DCCStablecoin(owner);
    }

    function testReverOnMintToZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__NotZeroAddress.selector);
        dccStablecoin.mint(address(0), amountToMint);
        vm.stopPrank();
    }

    function testMintAmountMustGreaterThanZero() public {
        vm.startPrank(owner);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__AmountMustBeGreaterThanZero.selector);
        dccStablecoin.mint(address(this), 0);
        vm.stopPrank();
    }

    function tesSuccesstmintDcc() public {
        vm.startPrank(owner);
        dccStablecoin.mint(address(this), amountToMint);
        vm.stopPrank();

        uint256 balance = dccStablecoin.balanceOf(address(this));
        assertEq(balance, amountToMint);
    }

    function testBurnAmountMustGreaterThanZero() public {
        vm.startPrank(owner);
        dccStablecoin.mint(address(this), amountToMint);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__AmountMustBeGreaterThanZero.selector);
        dccStablecoin.burn(0);
        vm.stopPrank();
    }

    function testBurnAmountCannotExceedTheBalance() public {
        vm.startPrank(owner);
        dccStablecoin.mint(address(this), amountToMint);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__BurnAmountExceedsBalance.selector);
        dccStablecoin.burn(101);
        vm.stopPrank();
    }

    function testFailedWhenUseBurnFrom() public {
        vm.prank(owner);
        vm.expectRevert(DCCStablecoin.DCCStablecoin__BlockFunction.selector);
        dccStablecoin.burnFrom(owner, amountToBurn);
        vm.stopPrank();
    }

    function testSuccesstBurnDcc() public {
        vm.startPrank(owner);
        dccStablecoin.mint(owner, amountToMint);
        dccStablecoin.burn(amountToBurn);
        vm.stopPrank();

        uint256 balance = dccStablecoin.balanceOf(owner);
        assertEq(balance, amountToMint - amountToBurn);
    }
}
