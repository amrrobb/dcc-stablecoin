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
    error DCCEngine__TokenAddressesAndCollateralInformationsAmountDontMatch();
    error DCCEngine__CollateralAlreadySet();
    error DCCEngine__NotAllowedToken(address tokenAddress);
    error DCCEngine__TransferFailed(address tokenAddress);
    error DCCEngine__MintFailed();
    error DCCEngine__BrokenHealthFactor(uint256 healthFactor);
    error DCCEngine__GoodHealthFactor();
    error DCCEngine__NotImprovedHealthFactor();
    error DCCEngine__ExcessDebtAmountToCover();
    error DCCEngine__ExcessCollateralToRedeem();

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

    uint256 private constant DCC_PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant MAX_HEALTH_FACTOR = type(uint256).max;

    // @dev mapping of collateral token address to collateral information
    mapping(address collateralToken => CollateralInformation) private s_colateralInformations;
    // @dev mapping the amount of collateral token deposited by user
    mapping(address user => mapping(address collateralToken => uint256 collateralAmount)) private s_collateralDeposited;
    // @dev mapping the amount of DCC token minted by user
    mapping(address user => uint256 dccAmount) private s_dccMinted;
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
    /**
     * @notice Modifier to ensure the provided amount is greater than zero.
     * @param amount The amount to check.
     * @dev Throws an error if the amount is zero.
     */
    modifier moreThanZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert DCCEngine__ShouldMoreThanZero();
        }
        _;
    }

    /**
     * @notice Modifier to ensure the provided collateral token address is allowed.
     * @param collateralTokenAddress The address of the collateral token.
     * @dev Throws an error if the collateral token address is not allowed.
     */
    modifier isAllowedToken(address collateralTokenAddress) {
        if (s_colateralInformations[collateralTokenAddress].priceFeed == address(0)) {
            revert DCCEngine__NotAllowedToken(collateralTokenAddress);
        }
        _;
    }

    /*//////////////////////////////////////////////////////
                          CONSTRUCTOR      
    //////////////////////////////////////////////////////*/
    constructor(
        address[] memory collateralTokenAddresses,
        CollateralInformation[] memory collateralInformations,
        address _sequencerUptimeFeed
    ) 
    /* Ownable(_owner) */
    {
        if (collateralTokenAddresses.length != collateralInformations.length) {
            revert DCCEngine__TokenAddressesAndCollateralInformationsAmountDontMatch();
        }
        uint256 length = collateralTokenAddresses.length;
        for (uint256 i = 0; i < length;) {
            if (s_colateralInformations[collateralTokenAddresses[i]].priceFeed != address(0)) {
                revert DCCEngine__CollateralAlreadySet();
            }
            s_colateralInformations[collateralTokenAddresses[i]] = collateralInformations[i];
            s_collateralTokens.push(collateralTokenAddresses[i]);
            unchecked {
                i++;
            }
        }

        i_dcc = new DCCStablecoin(address(this));
        i_sequencerUptimeFeed = _sequencerUptimeFeed;
    }

    /*//////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
                      EXTERNAL FUNCTIONS      
    ////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////*/

    /**
     * @notice Deposit Collateral and Mint DCC
     * @dev Calls the depositCollateral and mintDcc functions to handle the deposit and minting process in one transaction.
     * @notice Deposits a specified amount of collateral tokens and mints a corresponding amount of DCC tokens.
     * @param collateralTokenAddress The address of the collateral token to be deposited.
     * @param collateralAmount The amount of collateral tokens to be deposited.
     * @param dccAmountToMint The amount of DCC tokens to be minted.
     */
    function depositCollateralAndMintDcc(
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 dccAmountToMint
    ) external {
        depositCollateral(collateralTokenAddress, collateralAmount);
        mintDcc(dccAmountToMint);
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
    function redeemCollateralForDcc(address collateralTokenAddress, uint256 collateralAmount, uint256 dccAmountToBurn)
        external
        moreThanZeroAmount(collateralAmount)
        moreThanZeroAmount(dccAmountToBurn)
        isAllowedToken(collateralTokenAddress)
    {
        _burnDcc(dccAmountToBurn, msg.sender, msg.sender);
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender);
    }

    /**
     * @notice Redeems collateral tokens from the protocol.
     * @param collateralTokenAddress The address of the collateral token.
     * @param collateralAmount The amount of collateral tokens to redeem.
     * @dev Throws an error if the collateral amount is zero, the collateral token is not allowed, or if the function is reentrant.
     */
    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount)
        external
        moreThanZeroAmount(collateralAmount)
        isAllowedToken(collateralTokenAddress)
        nonReentrant
    {
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender);
    }

    /**
     * @dev Function to burn DCC tokens
     * @notice Burns a specified amount of DCC tokens and checks for health factor violation
     * @param dccAmountToBurn The amount of DCC tokens to be burned
     * @dev This function is sensitive as it permanently destroys DCC tokens. Exercise caution when using it.
     * @dev Use this only if you are worried about getting liquidated and want to burn DCC tokens but keep your collateral in
     */
    function burnDcc(uint256 dccAmountToBurn) external moreThanZeroAmount(dccAmountToBurn) {
        _burnDcc(dccAmountToBurn, msg.sender, msg.sender);
        // _revertIfBrokenHealthFactor(msg.sender); // I don't think this would ever hit...
    }

    /**
     * @dev This function allows for the partial liquidation of a user.
     * @param user The user who is insolvent, with a _healthFactor below MIN_HEALTH_FACTOR.
     * @param collateralTokenAddress The ERC20 token address of the collateral used to make the protocol solvent again.
     * This collateral is taken from the insolvent user.
     * In return, DSC is burned to pay off the user's debt, without paying off your own.
     * @param debtAmountToCover The amount of DCC tokens to burn in order to cover the user's debt.
     *
     * @notice A 10% LIQUIDATION_BONUS is received for seizing the user's funds.
     * @notice This function assumes the protocol is roughly 150% overcollateralized for effective operation.
     * @notice A known bug would occur if the protocol were only 100% collateralized, rendering liquidation impossible.
     *         For instance, if the price of the collateral plummeted before liquidation.
     */
    function liquidate(address user, address collateralTokenAddress, uint256 debtAmountToCover)
        external
        moreThanZeroAmount(debtAmountToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DCCEngine__GoodHealthFactor();
        }
        if (debtAmountToCover > s_dccMinted[user]) {
            revert DCCEngine__ExcessDebtAmountToCover();
        }
        uint256 tokenAmountToCover = _getTokenAmountFromUsdValue(collateralTokenAddress, debtAmountToCover);
        // total amount to cover * (100 + bonus) / 100
        uint256 totalCollateralToRedeem =
            (tokenAmountToCover * (LIQUIDATION_BONUS + LIQUIDATION_PRECISION)) / LIQUIDATION_PRECISION;

        if (totalCollateralToRedeem > s_collateralDeposited[user][collateralTokenAddress]) {
            revert DCCEngine__ExcessCollateralToRedeem();
        }
        _burnDcc(debtAmountToCover, user, msg.sender);
        _redeemCollateral(collateralTokenAddress, totalCollateralToRedeem, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DCCEngine__NotImprovedHealthFactor();
        }
        _revertIfBrokenHealthFactor(msg.sender);
    }

    /*//////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
                      PUBLIC FUNCTIONS      
    ////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////*/

    /**
     * @notice Deposits collateral tokens into the protocol.
     * @param collateralTokenAddress The address of the collateral token.
     * @param collateralAmount The amount of collateral tokens to deposit.
     * @dev Throws an error if the collateral amount is zero, the collateral token is not allowed, or if the function is reentrant.
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
     * @notice Mints DCC tokens based on deposited collateralized tokens.
     * @dev Can only mint DCC if there is enough collateral.
     * @param dccAmountToMint The amount of DCC tokens to mint.
     * @dev Throws an error if the DCC amount is zero or if the function is reentrant.
     */
    function mintDcc(uint256 dccAmountToMint) public moreThanZeroAmount(dccAmountToMint) nonReentrant {
        s_dccMinted[msg.sender] += dccAmountToMint;
        _revertIfBrokenHealthFactor(msg.sender);
        bool minted = i_dcc.mint(msg.sender, dccAmountToMint);

        if (!minted) {
            revert DCCEngine__MintFailed();
        }
    }

    /*//////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
                      PRIVATE FUNCTIONS      
    ////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////*/

    /**
     * @dev Redeems collateral tokens.
     * @param collateralTokenAddress The address of the collateral token.
     * @param collateralAmount The amount of collateral tokens to redeem.
     * @param redeemFrom The address from which collateral is redeemed.
     * @param redeemTo The address to which collateral is redeemed.
     * @dev Updates collateral records and emits a CollateralRedeemed event.
     * @dev Throws an error if the transfer of collateral tokens fails.
     */
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
     * @dev Burns DCC tokens.
     * @param dccAmountToBurn The amount of DCC tokens to burn.
     * @param onBehalfOf The address on behalf of which DCC tokens are burned.
     * @param dccFrom The address from which DCC tokens are burned.
     * @dev Updates DCC minting records and burns DCC tokens.
     * @dev Throws an error if the transfer of DCC tokens fails.
     */
    function _burnDcc(uint256 dccAmountToBurn, address onBehalfOf, address dccFrom) private {
        s_dccMinted[onBehalfOf] -= dccAmountToBurn;

        bool success = i_dcc.transferFrom(dccFrom, address(this), dccAmountToBurn);
        if (!success) {
            revert DCCEngine__TransferFailed(address(i_dcc));
        }
        i_dcc.burn(dccAmountToBurn);
    }

    /*//////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////
             INTERNAL & PRIVATE PURE & VIEW FUNCTIONS      
    ////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////*/

    /**
     * @dev Calculates the user's health factor.
     * @param user The address of the user.
     * @return The calculated health factor value.
     * @notice If the user's health factor drops below "MIN_HEALTH_FACTOR", they may be liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDccMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDccMinted, collateralValueInUsd);
    }

    /**
     * @dev Calculates the health factor.
     * @param totalDccMinted The total amount of DCC tokens minted.
     * @param collateralValueInUsd The value of collateral in USD.
     * @return The calculated health factor value.
     */
    function _calculateHealthFactor(uint256 totalDccMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDccMinted == 0) return MAX_HEALTH_FACTOR;
        uint256 collateralAdjustedByThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
        return (collateralAdjustedByThreshold * DCC_PRECISION) / totalDccMinted;
    }

    /**
     * @dev Checks if the user's health factor is below the minimum threshold and reverts if true.
     * @param user The address of the user.
     */
    function _revertIfBrokenHealthFactor(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DCCEngine__BrokenHealthFactor(healthFactor);
        }
    }

    /**
     * @dev Retrieves the account information including the total DCC minted and collateral value in USD.
     * @param user The address of the user.
     * @return totalDccMinted The total amount of DCC tokens minted.
     * @return collateralValueInUsd The total collateral value in USD.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDccMinted, uint256 collateralValueInUsd)
    {
        totalDccMinted = s_dccMinted[user];
        collateralValueInUsd = _getCollateralValueOfUser(user);
    }

    /**
     * @dev Calculates the collateral value of the user in USD.
     * @param user The address of the user.
     * @return collateralValueInUsd The total collateral value in USD.
     */
    function _getCollateralValueOfUser(address user) private view returns (uint256 collateralValueInUsd) {
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

    /**
     * @dev Retrieves the USD value of the specified token amount.
     * @param tokenAddress The address of the token.
     * @param amount The amount of tokens.
     * @return The USD value of the token amount.
     */
    function _getUsdValueFromTokenAmount(address tokenAddress, uint256 amount) private view returns (uint256) {
        CollateralInformation storage collateralInfo = s_colateralInformations[tokenAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralInfo.priceFeed);

        int256 price = priceFeed.staleCheckLatestRoundData(collateralInfo.heartbeat, i_sequencerUptimeFeed);
        // ex 1 ETH = 2000 USD
        // return price from chainlink priceFeed will be 2000 * 1e8
        // value = amount * price * amount precision / value precision
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        // price eth / usd = 3000e8
        // amount eth = 15 e18
        // usd = (15 e18 * 3000 e8) * e18/ (e8 * e18)

        // price btc / usd = 2000e8
        // amount btc = 100 e8
        // usd = (100 e8 * 2000e8 * e18) / (e8 * e8)

        uint256 priceWithDecimals = uint256(price) * DCC_PRECISION / (10 ** priceFeed.decimals());
        return priceWithDecimals * amount / (10 ** collateralInfo.decimals);
    }

    /**
     * @dev Retrieves the token amount from the specified USD value.
     * @param tokenAddress The address of the token.
     * @param usdValue The USD value.
     * @return The token amount equivalent to the USD value.
     */
    function _getTokenAmountFromUsdValue(address tokenAddress, uint256 usdValue) private view returns (uint256) {
        CollateralInformation storage collateralInfo = s_colateralInformations[tokenAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralInfo.priceFeed);

        int256 price = priceFeed.staleCheckLatestRoundData(collateralInfo.heartbeat, i_sequencerUptimeFeed);
        // ex 1 ETH = 2000 USD
        // return price from chainlink priceFeed will be 2000 * 1e8
        // value = amount * price * amount precision / value precision
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        uint256 priceWithDecimals = (uint256(price) * DCC_PRECISION) / (10 ** priceFeed.decimals());
        return (usdValue * (10 ** collateralInfo.decimals)) / (priceWithDecimals);
    }

    /**
     * @dev Calculates the health factor based on the total minted DCC and collateral value in USD.
     * @param totalDccMinted The total amount of DCC minted.
     * @param collateralValueInUsd The total collateral value in USD.
     * @return The calculated health factor.
     */
    function calculateHealthFactor(uint256 totalDccMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDccMinted, collateralValueInUsd);
    }

    /**
     * @dev Retrieves the liquidation bonus.
     * @return The liquidation bonus percentage.
     */
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /**
     * @dev Retrieves the liquidation threshold.
     * @return The liquidation threshold.
     */
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    /**
     * @dev Retrieves the liquidation precision.
     * @return The liquidation precision.
     */
    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    /**
     * @dev Retrieves the minimum health factor.
     * @return The minimum health factor.
     */
    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    /**
     * @dev Retrieves the maximum health factor.
     * @return The maximum health factor.
     */
    function getMaxHealthFactor() external pure returns (uint256) {
        return MAX_HEALTH_FACTOR;
    }

    /**
     * @dev Retrieves the address of the DCC token.
     * @return The address of the DCC token contract.
     */
    function getDccAddress() external view returns (address) {
        return address(i_dcc);
    }

    /**
     * @dev Retrieves the precision of DCC.
     * @return The precision of DCC.
     */
    function getDccPrecision() external pure returns (uint256) {
        return DCC_PRECISION;
    }

    /**
     * @dev Retrieves the USD value of the specified token amount.
     * @param tokenAddress The address of the token.
     * @param amount The amount of tokens.
     * @return The USD value of the token amount.
     */
    function getUsdValueFromTokenAmount(address tokenAddress, uint256 amount) external view returns (uint256) {
        return _getUsdValueFromTokenAmount(tokenAddress, amount);
    }

    /**
     * @dev Retrieves the token amount from the specified USD value.
     * @param tokenAddress The address of the token.
     * @param usdValue The USD value.
     * @return The token amount equivalent to the USD value.
     */
    function getTokenAmountFromUsdValue(address tokenAddress, uint256 usdValue) external view returns (uint256) {
        return _getTokenAmountFromUsdValue(tokenAddress, usdValue);
    }

    /**
     * @dev Retrieves the health factor of the specified user.
     * @param user The address of the user.
     * @return The health factor of the user.
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /**
     * @dev Retrieves the account information of the specified user.
     * @param user The address of the user.
     * @return totalDccMinted The total amount of DCC minted by the user.
     * @return collateralValueInUsd The total collateral value in USD deposited by the user.
     */
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDccMinted, uint256 collateralValueInUsd)
    {
        (totalDccMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    /**
     * @dev Retrieves the collateral information of the specified collateral token.
     * @param collateralTokenAddress The address of the collateral token.
     * @return The collateral information.
     */
    function getCollateralInformation(address collateralTokenAddress)
        external
        view
        returns (CollateralInformation memory)
    {
        return s_colateralInformations[collateralTokenAddress];
    }

    /**
     * @dev Retrieves the list of collateral tokens.
     * @return The list of collateral token addresses.
     */
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     * @dev Retrieves the collateral balance of the specified user for the specified collateral token.
     * @param user The address of the user.
     * @param collateralTokenAddress The address of the collateral token.
     * @return The collateral balance of the user for the specified collateral token.
     */
    function getCollateralBalanceOfUser(address user, address collateralTokenAddress) external view returns (uint256) {
        return s_collateralDeposited[user][collateralTokenAddress];
    }

    /**
     * @dev Retrieves the total collateral value in USD for the specified user.
     * @param user The address of the user.
     * @return The total collateral value in USD.
     */
    function getCollateralValueOfUser(address user) public view returns (uint256) {
        return _getCollateralValueOfUser(user);
    }
}
