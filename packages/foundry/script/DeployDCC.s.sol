//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {DCCEngine} from "../contracts/DCCEngine.sol";
import {DCCStablecoin} from "../contracts/DCCStablecoin.sol";
import {ScaffoldETHDeploy, console} from "./DeployHelpers.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDCCScript is ScaffoldETHDeploy {
    error InvalidPrivateKey(string);

    address[] public collateralTokenAddresses;
    address[] public priceFeedAddresses;
    uint8[] public collateralTokendDecimals;
    string[] public tokenNames;
    /*, address _owner */

    function run()
        external
        returns (DCCEngine dccEngine, DCCStablecoin dccStablecoin, HelperConfig config, uint256 deployerPrivateKey)
    {
        deployerPrivateKey = setupLocalhostEnv();
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set DEPLOYER_PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }

        config = new HelperConfig();

        tokenNames = config.getTokenNames();
        for (uint256 i = 0; i < tokenNames.length; i++) {
            (address tokenAddress, address priceFeed, uint8 decimals) = config.getActiveNetworkConfig(tokenNames[i]);

            collateralTokenAddresses.push(tokenAddress);
            priceFeedAddresses.push(priceFeed);
            collateralTokendDecimals.push(decimals);
        }

        vm.startBroadcast(deployerPrivateKey);
        dccEngine = new DCCEngine(
            collateralTokenAddresses, priceFeedAddresses, collateralTokendDecimals
        );
        console.logString(string.concat("DCCEngine deployed at: ", vm.toString(address(dccEngine))));

        address dccTokenAddress = dccEngine.getDCCAddress();
        dccStablecoin = DCCStablecoin(dccTokenAddress);
        console.logString(string.concat("DCCStablecoin deployed at: ", vm.toString(dccTokenAddress)));

        vm.stopBroadcast();

        /**
         * This function generates the file containing the contracts Abi definitions.
         * These definitions are used to derive the types needed in the custom scaffold-eth hooks, for example.
         * This function should be called last.
         */
        exportDeployments();
    }

    function getDeployedParameters()
        public
        view
        returns (address[] memory, address[] memory, uint8[] memory, string[] memory)
    {
        return (collateralTokenAddresses, priceFeedAddresses, collateralTokendDecimals, tokenNames);
    }
}
