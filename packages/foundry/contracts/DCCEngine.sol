// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DCCStablecoin} from "./DCCStablecoin.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DCCEngine
 * @author Ammar Robbani (Robbyn)
 * @dev This contract is the core system of the DCCStablecoin contract.
 *
 * The system simply designed similarly to DAI with slightly differencies:
 *      - no governance
 *      - no fees
 *      - backed by only WETH and WBTC
 *
 * The token always mantain the value of 1 dollar (1 DCC = $ 1.00 USD) at all times.
 * The DCC stablecoin follows the properties:
 *      - Dollar Pegged
 *      - Exogenously Collateralized
 *      - Algorithmically Stable
 *
 * @notice This contarct handles all logic for minting and redeeming DCC as well as depositing and withdrawing collateral
 * @notice This contract is based on the MakerDAO DSS (Dai Stablecoin System). Reference: https://github.com/makerdao/dss
 */

contract DCCEngine is ReentrancyGuard /*, Ownable */ {
    /*//////////////////////////////////////////////////////
                           ERRORS      
    //////////////////////////////////////////////////////*/
    error DCCEngine__ShouldMoreThanZero();
    error DCCEngine__TokenAddressesAndCollateralInforamtionsAmountDontMatch();
    // error DCCEngine__TokenAddressesAndTokenDecimalsAmountsDontMatch();
    error DCCEngine__NotAllowedToken(address tokenAddress);
    error DCCEngine__TransferFailed(address tokenAddress);
    error DCCEngine__MintFailed();
    error DCCEngine__BrokenHealthFactor(uint256 healthFactor);
    error DCCEngine__GoodHealthFactor();
    error DCCEngine__NotImprovedHealthFactor();
    error DCCEngine__ExcessDebtAmountToCover();

    /*//////////////////////////////////////////////////////
                          LIBRARIES      
    //////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////
                       TYPE DECLARATIONS      
    //////////////////////////////////////////////////////*/
    /**
     * @dev struct for chainlink price feed and decimals of collateral token
     * For information about struct properties, see:
     * pricefeed: https://docs.chain.link/data-feeds/price-feeds
     * heartbeat: https://docs.chain.link/data-feeds#check-the-timestamp-of-the-latest-answer
     */
    struct CollateralInformation {
        address priceFeed;
        uint8 decimals;
        uint256 heartbeat;
    }

    /*//////////////////////////////////////////////////////
                        STATE VARIABLES      
    //////////////////////////////////////////////////////*/
    /**
     * Chainlink variable
     * For a list of available Sequencer Uptime Feed proxy addresses, see:
     * https://docs.chain.link/docs/data-feeds/l2-sequencer-feeds
     */
    address private immutable i_sequencerUptimeFeed;
    DCCStablecoin private immutable i_dcc;

    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;

    uint256 private constant PRICE_FEED_ADDITIONAL_PRECISION = 1e10;
    uint256 private constant DCC_PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant MAX_HEALTH_FACTOR = type(uint256).max;

    // @dev mapping of collateral token address to collateral information
    mapping(address collateralToken => CollateralInformation) private s_colateralInformations;
    // @dev mapping the amount of collateral token deposited by user
    mapping(address user => mapping(address collateralToken => uint256 collateralAmount)) private s_collateralDeposited;
    // @dev mapping the amount of DCC token minted by user
    mapping(address user => uint256 dccAmount) private s_DCCMinted;
    // @dev array of address of collateral tokens
    address[] private s_collateralTokens;

    /*//////////////////////////////////////////////////////
                           EVENTS      
    //////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed collateralToken, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemFrom, address indexed redeemTo, address indexed collateralToken, uint256 amount
    );

    /*//////////////////////////////////////////////////////
                          MODIFIERS      
    //////////////////////////////////////////////////////*/
    modifier moreThanZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert DCCEngine__ShouldMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address collateralTokenAddress) {
        if (s_colateralInformations[collateralTokenAddress].priceFeed == address(0)) {
            revert DCCEngine__NotAllowedToken(collateralTokenAddress);
        }
        _;
    }

    /*//////////////////////////////////////////////////////
                          FUNCTIONS      
    //////////////////////////////////////////////////////*/
    constructor(
        /**
         * address[] memory priceFeedAddresses, //address _owner
         * uint8[] memory collateralTokendDecimals,
         */
        address[] memory collateralTokenAddresses,
        CollateralInformation[] memory collateralInformations,
        address _sequencerUptimeFeed
    ) 
    /* Ownable(_owner) */
    {
        if (collateralTokenAddresses.length != collateralInformations.length) {
            revert DCCEngine__TokenAddressesAndCollateralInforamtionsAmountDontMatch();
        }
        uint256 length = collateralTokenAddresses.length;
        for (uint256 i = 0; i < length;) {
            s_colateralInformations[collateralTokenAddresses[i]] = collateralInformations[i];
            s_collateralTokens.push(collateralTokenAddresses[i]);
            unchecked {
                i++;
            }
        }

        i_dcc = new DCCStablecoin(address(this));
        i_sequencerUptimeFeed = _sequencerUptimeFeed;
    }

    /**
     * @dev Deposit Collateral and Mint DCC
     * @dev Calls the depositCollateral and mintDCC functions to handle the deposit and minting process in one transaction.
     * @notice Deposits a specified amount of collateral tokens and mints a corresponding amount of DCC tokens.
     * @param collateralTokenAddress The address of the collateral token to be deposited.
     * @param collateralAmount The amount of collateral tokens to be deposited.
     * @param dccAmountToMint The amount of DCC tokens to be minted.
     */
    function depositCollateralAndMintDCC(
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 dccAmountToMint
    ) external {
        depositCollateral(collateralTokenAddress, collateralAmount);
        mintDCC(dccAmountToMint);
    }

    /**
     * @param collateralTokenAddress the address of the token that want to be deposited as collateral
     * @param collateralAmount the amount of collateral to deposit
     */
    function depositCollateral(address collateralTokenAddress, uint256 collateralAmount)
        public
        moreThanZeroAmount(collateralAmount)
        isAllowedToken(collateralTokenAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][collateralTokenAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, collateralTokenAddress, collateralAmount);
        bool success = IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DCCEngine__TransferFailed(collateralTokenAddress);
        }
    }

    /**
     * @notice Redeems collateral for DCC tokens
     * @dev Burns a specified amount of DCC tokens and redeems collateral in exchange
     * @param collateralTokenAddress The address of the collateral token to be redeemed
     * @param collateralAmount The amount of collateral tokens to be redeemed
     * @param dccAmountToBurn The amount of DCC tokens to be burned
     * @dev Requirements:
     * - The collateral amount and DCC amount to burn must be greater than zero
     * - The collateral token address must be allowed
     * @dev Caution: This function is sensitive as it permanently destroys DCC tokens. Exercise caution when using it.
     */
    function redeemCollateralForDCC(address collateralTokenAddress, uint256 collateralAmount, uint256 dccAmountToBurn)
        external
        moreThanZeroAmount(collateralAmount)
        moreThanZeroAmount(dccAmountToBurn)
        isAllowedToken(collateralTokenAddress)
    {
        _burnDCC(dccAmountToBurn, msg.sender, msg.sender);
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender);
    }

    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount)
        external
        moreThanZeroAmount(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender);
    }

    function _redeemCollateral(
        address collateralTokenAddress,
        uint256 collateralAmount,
        address redeemFrom,
        address redeemTo
    ) private {
        s_collateralDeposited[redeemFrom][collateralTokenAddress] -= collateralAmount;
        emit CollateralRedeemed(redeemFrom, redeemTo, collateralTokenAddress, collateralAmount);

        bool success = IERC20(collateralTokenAddress).transfer(redeemTo, collateralAmount);
        if (!success) {
            revert DCCEngine__TransferFailed(collateralTokenAddress);
        }
    }

    /**
     * @dev the funtion for minting DCC based on deposited collateralized token
     * @notice can only minted DCC if you have enough collateral
     * @param dccAmountToMint the amount of DCC token to mint
     */
    function mintDCC(uint256 dccAmountToMint) public moreThanZeroAmount(dccAmountToMint) nonReentrant {
        s_DCCMinted[msg.sender] += dccAmountToMint;
        _revertIfBrokenHealthFactor(msg.sender);
        bool minted = i_dcc.mint(msg.sender, dccAmountToMint);

        if (!minted) {
            revert DCCEngine__MintFailed();
        }
    }

    /**
     * @dev Function to burn DCC tokens
     * @notice Burns a specified amount of DCC tokens and checks for health factor violation
     * @param dccAmountToBurn The amount of DCC tokens to be burned
     * @dev This function is sensitive as it permanently destroys DCC tokens. Exercise caution when using it.
     * @dev Use this only if you are worried about getting liquidated and want to burn DCC tokens but keep your collateral in
     */
    function burnDCC(uint256 dccAmountToBurn) external moreThanZeroAmount(dccAmountToBurn) {
        _burnDCC(dccAmountToBurn, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender); // I don't think this would ever hit...
    }

    function _burnDCC(uint256 dccAmountToBurn, address onBehalfOf, address dccFrom) private {
        s_DCCMinted[onBehalfOf] -= dccAmountToBurn;

        bool success = i_dcc.transferFrom(dccFrom, address(this), dccAmountToBurn);
        if (!success) {
            revert DCCEngine__TransferFailed(address(i_dcc));
        }
        i_dcc.burn(dccAmountToBurn);
    }

    /**
     * @dev This function allows for the partial liquidation of a user.
     * @param collateralTokenAddress The ERC20 token address of the collateral used to make the protocol solvent again.
     * This collateral is taken from the insolvent user.
     * In return, DSC is burned to pay off the user's debt, without paying off your own.
     * @param user The user who is insolvent, with a _healthFactor below MIN_HEALTH_FACTOR.
     * @param debtAmountToCover The amount of DCC tokens to burn in order to cover the user's debt.
     *
     * @notice A 10% LIQUIDATION_BONUS is received for seizing the user's funds.
     * @notice This function assumes the protocol is roughly 150% overcollateralized for effective operation.
     * @notice A known bug would occur if the protocol were only 100% collateralized, rendering liquidation impossible.
     *         For instance, if the price of the collateral plummeted before liquidation.
     */

    function liquidate(address collateralTokenAddress, address user, uint256 debtAmountToCover)
        external
        moreThanZeroAmount(debtAmountToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DCCEngine__GoodHealthFactor();
        }
        if (debtAmountToCover > s_collateralDeposited[user][collateralTokenAddress]) {
            revert DCCEngine__ExcessDebtAmountToCover();
        }
        uint256 tokenAmountToCover = _getTokenAmountFromUsdValue(collateralTokenAddress, debtAmountToCover);
        // total amount to cover * (100 + bonus) / 100
        uint256 totalCollateralToRedeem =
            (tokenAmountToCover * (LIQUIDATION_BONUS + LIQUIDATION_PRECISION)) / LIQUIDATION_PRECISION;

        _burnDCC(debtAmountToCover, user, msg.sender);
        _redeemCollateral(collateralTokenAddress, totalCollateralToRedeem, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DCCEngine__NotImprovedHealthFactor();
        }
        _revertIfBrokenHealthFactor(msg.sender);
    }

    /*//////////////////////////////////////////////////////
             INTERNAL & PRIVATE PURE & VIEW FUNCTIONS      
    //////////////////////////////////////////////////////*/
    /**
     * @dev this function calculates the value of health factor
     * @notice if user's health factor goes below "1", then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DCC minted
        // total collateral value
        (uint256 totalDccMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDccMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDccMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDccMinted == 0) return MAX_HEALTH_FACTOR;
        uint256 collateralAdjustedByThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return collateralAdjustedByThreshold * MIN_HEALTH_FACTOR / totalDccMinted;
    }

    function _revertIfBrokenHealthFactor(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DCCEngine__BrokenHealthFactor(healthFactor);
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDccMinted, uint256 collateralValueInUsd)
    {
        totalDccMinted = s_DCCMinted[user];
        collateralValueInUsd = _getAccountCollateralValue(user);
    }

    function _getAccountCollateralValue(address user) private view returns (uint256 collateralValueInUsd) {
        uint256 allowedToken = s_collateralTokens.length;
        for (uint256 i = 0; i < allowedToken;) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][tokenAddress];
            collateralValueInUsd = collateralValueInUsd + _getUsdValueFromTokenAmount(tokenAddress, amount);
            unchecked {
                i++;
            }
        }
    }

    function _getUsdValueFromTokenAmount(address tokenAddress, uint256 amount) private view returns (uint256) {
        CollateralInformation storage collateralInfo = s_colateralInformations[tokenAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralInfo.priceFeed);

        int256 price = priceFeed.staleCheckLatestRoundData(collateralInfo.heartbeat, i_sequencerUptimeFeed);

        // ex 1 ETH = 2000 USD
        // return price from chainlink priceFeed will be 2000 * 1e8
        // value = amount * price * amount precision / value precision
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return uint256(price) * PRICE_FEED_ADDITIONAL_PRECISION * amount / DCC_PRECISION;
    }

    function _getTokenAmountFromUsdValue(address tokenAddress, uint256 usdValue) private view returns (uint256) {
        CollateralInformation storage collateralInfo = s_colateralInformations[tokenAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralInfo.priceFeed);

        int256 price = priceFeed.staleCheckLatestRoundData(collateralInfo.heartbeat, i_sequencerUptimeFeed);
        // ex 1 ETH = 2000 USD
        // return price from chainlink priceFeed will be 2000 * 1e8
        // value = amount * price * amount precision / value precision
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return (usdValue * DCC_PRECISION) / (uint256(price) * PRICE_FEED_ADDITIONAL_PRECISION);
    }

    /*//////////////////////////////////////////////////////
             EXTERNAL & PUBLIC PURE & VIEW FUNCTIONS      
    //////////////////////////////////////////////////////*/
    function calculateHealthFactor(uint256 totalDccMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDccMinted, collateralValueInUsd);
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getMaxHealthFactor() external pure returns (uint256) {
        return MAX_HEALTH_FACTOR;
    }

    function getPriceFeedAdditionalPrecision() external pure returns (uint256) {
        return PRICE_FEED_ADDITIONAL_PRECISION;
    }

    function getDCCAddress() external view returns (address) {
        return address(i_dcc);
    }

    function getDCCPrecision() external pure returns (uint256) {
        return DCC_PRECISION;
    }

    function getUsdValueFromTokenAmount(address tokenAddress, uint256 amount) external view returns (uint256) {
        return _getUsdValueFromTokenAmount(tokenAddress, amount);
    }

    function getTokenAmountFromUsdValue(address tokenAddress, uint256 usdValue) external view returns (uint256) {
        return _getTokenAmountFromUsdValue(tokenAddress, usdValue);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDccMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getCollateralInformation(address collateralTokenAddress)
        external
        view
        returns (CollateralInformation memory)
    {
        return s_colateralInformations[collateralTokenAddress];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address collateralTokenAddress) external view returns (uint256) {
        return s_collateralDeposited[user][collateralTokenAddress];
    }
}
