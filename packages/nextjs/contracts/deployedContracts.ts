/**
 * This file is autogenerated by Scaffold-ETH.
 * You should not edit it manually or your changes might be overwritten.
 */
import { GenericContractsDeclaration } from "~~/utils/scaffold-eth/contract";

const deployedContracts = {
  31337: {
    OracleLib: {
      address: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
      abi: [
        {
          inputs: [],
          name: "OracleLib__GracePeriodNotOver",
          type: "error",
        },
        {
          inputs: [],
          name: "OracleLib__SequencerDown",
          type: "error",
        },
        {
          inputs: [],
          name: "OracleLib__StalePrice",
          type: "error",
        },
        {
          inputs: [
            {
              internalType: "contract AggregatorV3Interface",
              name: "priceFeed",
              type: "AggregatorV3Interface",
            },
            {
              internalType: "uint256",
              name: "heartbeat",
              type: "uint256",
            },
            {
              internalType: "address",
              name: "sequencerUptimeFeedAddress",
              type: "address",
            },
          ],
          name: "staleCheckLatestRoundData",
          outputs: [
            {
              internalType: "int256",
              name: "",
              type: "int256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
      ],
      inheritedFunctions: {},
    },
    DCCEngine: {
      address: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
      abi: [
        {
          inputs: [
            {
              internalType: "address[]",
              name: "collateralTokenAddresses",
              type: "address[]",
            },
            {
              components: [
                {
                  internalType: "address",
                  name: "priceFeed",
                  type: "address",
                },
                {
                  internalType: "uint8",
                  name: "decimals",
                  type: "uint8",
                },
                {
                  internalType: "uint256",
                  name: "heartbeat",
                  type: "uint256",
                },
              ],
              internalType: "struct DCCEngine.CollateralInformation[]",
              name: "collateralInformations",
              type: "tuple[]",
            },
            {
              internalType: "address",
              name: "_sequencerUptimeFeed",
              type: "address",
            },
          ],
          stateMutability: "nonpayable",
          type: "constructor",
        },
        {
          inputs: [
            {
              internalType: "uint256",
              name: "healthFactor",
              type: "uint256",
            },
          ],
          name: "DCCEngine__BrokenHealthFactor",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__CollateralAlreadySet",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__ExcessCollateralToRedeem",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__ExcessDebtAmountToCover",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__GoodHealthFactor",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__MintFailed",
          type: "error",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "tokenAddress",
              type: "address",
            },
          ],
          name: "DCCEngine__NotAllowedToken",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__NotImprovedHealthFactor",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__ShouldMoreThanZero",
          type: "error",
        },
        {
          inputs: [],
          name: "DCCEngine__TokenAddressesAndCollateralInformationsAmountDontMatch",
          type: "error",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "tokenAddress",
              type: "address",
            },
          ],
          name: "DCCEngine__TransferFailed",
          type: "error",
        },
        {
          inputs: [],
          name: "ReentrancyGuardReentrantCall",
          type: "error",
        },
        {
          anonymous: false,
          inputs: [
            {
              indexed: true,
              internalType: "address",
              name: "user",
              type: "address",
            },
            {
              indexed: true,
              internalType: "address",
              name: "collateralToken",
              type: "address",
            },
            {
              indexed: true,
              internalType: "uint256",
              name: "amount",
              type: "uint256",
            },
          ],
          name: "CollateralDeposited",
          type: "event",
        },
        {
          anonymous: false,
          inputs: [
            {
              indexed: true,
              internalType: "address",
              name: "redeemFrom",
              type: "address",
            },
            {
              indexed: true,
              internalType: "address",
              name: "redeemTo",
              type: "address",
            },
            {
              indexed: true,
              internalType: "address",
              name: "collateralToken",
              type: "address",
            },
            {
              indexed: false,
              internalType: "uint256",
              name: "amount",
              type: "uint256",
            },
          ],
          name: "CollateralRedeemed",
          type: "event",
        },
        {
          inputs: [
            {
              internalType: "uint256",
              name: "dccAmountToBurn",
              type: "uint256",
            },
          ],
          name: "burnDcc",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "uint256",
              name: "totalDccMinted",
              type: "uint256",
            },
            {
              internalType: "uint256",
              name: "collateralValueInUsd",
              type: "uint256",
            },
          ],
          name: "calculateHealthFactor",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "pure",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "collateralTokenAddress",
              type: "address",
            },
            {
              internalType: "uint256",
              name: "collateralAmount",
              type: "uint256",
            },
          ],
          name: "depositCollateral",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "collateralTokenAddress",
              type: "address",
            },
            {
              internalType: "uint256",
              name: "collateralAmount",
              type: "uint256",
            },
            {
              internalType: "uint256",
              name: "dccAmountToMint",
              type: "uint256",
            },
          ],
          name: "depositCollateralAndMintDcc",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "user",
              type: "address",
            },
          ],
          name: "getAccountInformation",
          outputs: [
            {
              internalType: "uint256",
              name: "totalDccMinted",
              type: "uint256",
            },
            {
              internalType: "uint256",
              name: "collateralValueInUsd",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "user",
              type: "address",
            },
            {
              internalType: "address",
              name: "collateralTokenAddress",
              type: "address",
            },
          ],
          name: "getCollateralBalanceOfUser",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "collateralTokenAddress",
              type: "address",
            },
          ],
          name: "getCollateralInformation",
          outputs: [
            {
              components: [
                {
                  internalType: "address",
                  name: "priceFeed",
                  type: "address",
                },
                {
                  internalType: "uint8",
                  name: "decimals",
                  type: "uint8",
                },
                {
                  internalType: "uint256",
                  name: "heartbeat",
                  type: "uint256",
                },
              ],
              internalType: "struct DCCEngine.CollateralInformation",
              name: "",
              type: "tuple",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "getCollateralTokens",
          outputs: [
            {
              internalType: "address[]",
              name: "",
              type: "address[]",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "user",
              type: "address",
            },
          ],
          name: "getCollateralValueOfUser",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "getDccAddress",
          outputs: [
            {
              internalType: "address",
              name: "",
              type: "address",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "getDccPrecision",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "pure",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "user",
              type: "address",
            },
          ],
          name: "getHealthFactor",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [],
          name: "getLiquidationBonus",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "pure",
          type: "function",
        },
        {
          inputs: [],
          name: "getLiquidationPrecision",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "pure",
          type: "function",
        },
        {
          inputs: [],
          name: "getLiquidationThreshold",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "pure",
          type: "function",
        },
        {
          inputs: [],
          name: "getMaxHealthFactor",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "pure",
          type: "function",
        },
        {
          inputs: [],
          name: "getMinHealthFactor",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "pure",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "tokenAddress",
              type: "address",
            },
            {
              internalType: "uint256",
              name: "usdValue",
              type: "uint256",
            },
          ],
          name: "getTokenAmountFromUsdValue",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "tokenAddress",
              type: "address",
            },
            {
              internalType: "uint256",
              name: "amount",
              type: "uint256",
            },
          ],
          name: "getUsdValueFromTokenAmount",
          outputs: [
            {
              internalType: "uint256",
              name: "",
              type: "uint256",
            },
          ],
          stateMutability: "view",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "user",
              type: "address",
            },
            {
              internalType: "address",
              name: "collateralTokenAddress",
              type: "address",
            },
            {
              internalType: "uint256",
              name: "debtAmountToCover",
              type: "uint256",
            },
          ],
          name: "liquidate",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "uint256",
              name: "dccAmountToMint",
              type: "uint256",
            },
          ],
          name: "mintDcc",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "collateralTokenAddress",
              type: "address",
            },
            {
              internalType: "uint256",
              name: "collateralAmount",
              type: "uint256",
            },
          ],
          name: "redeemCollateral",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
        {
          inputs: [
            {
              internalType: "address",
              name: "collateralTokenAddress",
              type: "address",
            },
            {
              internalType: "uint256",
              name: "collateralAmount",
              type: "uint256",
            },
            {
              internalType: "uint256",
              name: "dccAmountToBurn",
              type: "uint256",
            },
          ],
          name: "redeemCollateralForDcc",
          outputs: [],
          stateMutability: "nonpayable",
          type: "function",
        },
      ],
      inheritedFunctions: {},
    },
  },
} as const;

export default deployedContracts satisfies GenericContractsDeclaration;
