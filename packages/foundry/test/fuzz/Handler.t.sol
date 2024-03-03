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

contract Handler is Test {}
