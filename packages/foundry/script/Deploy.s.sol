//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import {DeployDCCScript} from "./DeployDCC.s.sol";

contract DeployScript is ScaffoldETHDeploy {
    function run() external {
        // Deploy Defi DCC Stablecoin contract
        DeployDCCScript dccScript = new DeployDCCScript();
        vm.allowCheatcodes(address(dccScript));
        dccScript.run();
    }

    function test() public {}
}
