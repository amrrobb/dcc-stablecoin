// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DCCStablecoin
 * @author Ammar Robbani (Robbyn)
 * @dev Stablecoin that follows this 3 main properties:
 * - Relative stability: Pegged to USD -> $1.00
 * - Stability mechanism: Algoritmic
 *      People can only mint the stablecoin with enough collateral
 * - Collateral type: Exogneous (cryptocurrency)
 *      1. wETH
 *      2. wBTC
 * @notice This contract meant to be owned by DCCEngine. An ERC20 that can be minted and burned through DCCEngine contract.
 */

contract DCCStablecoin is ERC20, ERC20Burnable, Ownable {
    error DCCStablecoin__NotZeroAddress();
    error DCCStablecoin__AmountMustBeGreaterThanZero();
    error DCCStablecoin__BurnAmountExceedsBalance();
    error DCCStablecoin__BlockFunction();

    constructor(address initialOwner) ERC20("Decentralized Coin", "DCC") Ownable(initialOwner) {}

    function mint(address to, uint256 amount) public onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DCCStablecoin__NotZeroAddress();
        }
        if (amount <= 0) {
            revert DCCStablecoin__AmountMustBeGreaterThanZero();
        }
        _mint(to, amount);
        return true;
    }

    function burnFrom(address, /* from */ uint256 /* amount */ ) public pure override {
        revert DCCStablecoin__BlockFunction();
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DCCStablecoin__AmountMustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DCCStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
