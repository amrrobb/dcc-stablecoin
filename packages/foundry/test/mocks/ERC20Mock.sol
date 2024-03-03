// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {ERC20Mock as mockERC20} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
// import {ERC20DecimalsMock} from "@openzeppelin/contracts/mocks/token/ERC20DecimalsMock.sol";

// contract ERC20Mock is ERC20, ERC20DecimalsMock {
//     constructor( /*string memory name, string memory symbol, */ uint8 decimals_)
//         ERC20("", "")
//         ERC20DecimalsMock(decimals_)
//     {}

//     function decimals() public view override(ERC20) returns (uint8) {
//         return super.decimals();
//     }
// }

contract ERC20Mock is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }
}
