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
    //////////////////////////////
    //////      Errors      //////
    //////////////////////////////
    error DCCEngine__ShouldMoreThanZero();
    error DCCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DCCEngine__TokenAddressesAndTokenDecimalsAmountsDontMatch();
    error DCCEngine__NotAllowedToken(address tokenAddress);
    error DCCEngine__TransferFailed(address tokenAddress);
    error DCCEngine__MintFailed();
    error DCCEngine__BrokenHealthFactor(uint256 healthFactor);
    error DCCEngine__GoodHealthFactor();
    error DCCEngine__NotImprovedHealthFactor();
    error DCCEngine__ExcessDebtAmountToCover();

    //////////////////////////////////
    //////      Libraries       //////
    //////////////////////////////////

    //////////////////////////////////////////
    //////      Type Declarations       //////
    //////////////////////////////////////////
    // @dev struct for chainlink price feed and decimals of collateral token
    struct CollateralInfo {
        address priceFeed;
        uint8 decimals;
    }

    ////////////////////////////////////////
    //////      State Variables       //////
    ////////////////////////////////////////
    DCCStablecoin private immutable i_dcc;

    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;

    uint256 private constant PRICE_FEED_ADDITIONAL_PRECISION = 1e10;
    uint256 private constant DCC_PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant MAX_HEALTH_FACTOR = type(uint256).max;

    // @dev mapping of collateral token address to collateral information
    mapping(address collateralToken => CollateralInfo) private s_colateralInfos;
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
    modifier moreThanZeroAmount(uint256 _amount) {
        if (_amount == 0) {
            revert DCCEngine__ShouldMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _collateralTokenAddress) {
        if (s_colateralInfos[_collateralTokenAddress].priceFeed == address(0)) {
            revert DCCEngine__NotAllowedToken(_collateralTokenAddress);
        }
        _;
    }

    /*//////////////////////////////////////////////////////
                          FUNCTIONS      
    //////////////////////////////////////////////////////*/
    constructor(
        address[] memory _collateralTokenAddresses,
        address[] memory _priceFeedAddresses, /*, address _owner */
        uint8[] memory _collateralTokendDecimals
    ) 
    /* Ownable(_owner) */
    {
        if (_collateralTokenAddresses.length != _priceFeedAddresses.length) {
            revert DCCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        if (_collateralTokenAddresses.length != _collateralTokendDecimals.length) {
            revert DCCEngine__TokenAddressesAndTokenDecimalsAmountsDontMatch();
        }
        uint256 length = _collateralTokenAddresses.length;
        for (uint256 i = 0; i < length;) {
            s_colateralInfos[_collateralTokenAddresses[i]] =
                CollateralInfo({priceFeed: _priceFeedAddresses[i], decimals: _collateralTokendDecimals[i]});
            s_collateralTokens.push(_collateralTokenAddresses[i]);

            unchecked {
                i++;
            }
        }

        i_dcc = new DCCStablecoin(address(this));
    }

    /**
     * @dev Deposit Collateral and Mint DCC
     * @dev Calls the depositCollateral and mintDCC functions to handle the deposit and minting process in one transaction.
     * @notice Deposits a specified amount of collateral tokens and mints a corresponding amount of DCC tokens.
     * @param _collateralTokenAddress The address of the collateral token to be deposited.
     * @param _collateralAmount The amount of collateral tokens to be deposited.
     * @param _dccAmountToMint The amount of DCC tokens to be minted.
     */
    function depositCollateralAndMintDCC(
        address _collateralTokenAddress,
        uint256 _collateralAmount,
        uint256 _dccAmountToMint
    ) external {
        depositCollateral(_collateralTokenAddress, _collateralAmount);
        mintDCC(_dccAmountToMint);
    }

    /**
     * @param _collateralTokenAddress the address of the token that want to be deposited as collateral
     * @param _collateralAmount the amount of collateral to deposit
     */
    function depositCollateral(address _collateralTokenAddress, uint256 _collateralAmount)
        public
        moreThanZeroAmount(_collateralAmount)
        isAllowedToken(_collateralTokenAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_collateralTokenAddress] += _collateralAmount;
        emit CollateralDeposited(msg.sender, _collateralTokenAddress, _collateralAmount);
        bool success = IERC20(_collateralTokenAddress).transferFrom(msg.sender, address(this), _collateralAmount);
        if (!success) {
            revert DCCEngine__TransferFailed(_collateralTokenAddress);
        }
    }

    /**
     * @notice Redeems collateral for DCC tokens
     * @dev Burns a specified amount of DCC tokens and redeems collateral in exchange
     * @param _collateralTokenAddress The address of the collateral token to be redeemed
     * @param _collateralAmount The amount of collateral tokens to be redeemed
     * @param _dccAmountToBurn The amount of DCC tokens to be burned
     * @dev Requirements:
     * - The collateral amount and DCC amount to burn must be greater than zero
     * - The collateral token address must be allowed
     * @dev Caution: This function is sensitive as it permanently destroys DCC tokens. Exercise caution when using it.
     */
    function redeemCollateralForDCC(
        address _collateralTokenAddress,
        uint256 _collateralAmount,
        uint256 _dccAmountToBurn
    )
        external
        moreThanZeroAmount(_collateralAmount)
        moreThanZeroAmount(_dccAmountToBurn)
        isAllowedToken(_collateralTokenAddress)
    {
        _burnDCC(_dccAmountToBurn, msg.sender, msg.sender);
        _redeemCollateral(_collateralTokenAddress, _collateralAmount, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender);
    }

    function redeemCollateral(address _collateralTokenAddress, uint256 _collateralAmount)
        external
        moreThanZeroAmount(_collateralAmount)
        nonReentrant
    {
        _redeemCollateral(_collateralTokenAddress, _collateralAmount, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender);
    }

    function _redeemCollateral(
        address _collateralTokenAddress,
        uint256 _collateralAmount,
        address redeemFrom,
        address redeemTo
    ) private {
        s_collateralDeposited[redeemFrom][_collateralTokenAddress] -= _collateralAmount;
        emit CollateralRedeemed(redeemFrom, redeemTo, _collateralTokenAddress, _collateralAmount);

        bool success = IERC20(_collateralTokenAddress).transfer(redeemTo, _collateralAmount);
        if (!success) {
            revert DCCEngine__TransferFailed(_collateralTokenAddress);
        }
    }

    /**
     * @dev the funtion for minting DCC based on deposited collateralized token
     * @notice can only minted DCC if you have enough collateral
     * @param _dccAmountToMint the amount of DCC token to mint
     */
    function mintDCC(uint256 _dccAmountToMint) public moreThanZeroAmount(_dccAmountToMint) nonReentrant {
        s_DCCMinted[msg.sender] += _dccAmountToMint;
        _revertIfBrokenHealthFactor(msg.sender);
        bool minted = i_dcc.mint(msg.sender, _dccAmountToMint);

        if (!minted) {
            revert DCCEngine__MintFailed();
        }
    }

    /**
     * @dev Function to burn DCC tokens
     * @notice Burns a specified amount of DCC tokens and checks for health factor violation
     * @param _dccAmountToBurn The amount of DCC tokens to be burned
     * @dev This function is sensitive as it permanently destroys DCC tokens. Exercise caution when using it.
     * @dev Use this only if you are worried about getting liquidated and want to burn DCC tokens but keep your collateral in
     */
    function burnDCC(uint256 _dccAmountToBurn) external moreThanZeroAmount(_dccAmountToBurn) {
        _burnDCC(_dccAmountToBurn, msg.sender, msg.sender);
        _revertIfBrokenHealthFactor(msg.sender); // I don't think this would ever hit...
    }

    function _burnDCC(uint256 _dccAmountToBurn, address onBehalfOf, address dccFrom) private {
        s_DCCMinted[onBehalfOf] -= _dccAmountToBurn;

        bool success = i_dcc.transferFrom(dccFrom, address(this), _dccAmountToBurn);
        if (!success) {
            revert DCCEngine__TransferFailed(address(i_dcc));
        }
        i_dcc.burn(_dccAmountToBurn);
    }

    /**
     * @dev This function allows for the partial liquidation of a user.
     * @param _collateralTokenAddress The ERC20 token address of the collateral used to make the protocol solvent again.
     * This collateral is taken from the insolvent user.
     * In return, DSC is burned to pay off the user's debt, without paying off your own.
     * @param user The user who is insolvent, with a _healthFactor below MIN_HEALTH_FACTOR.
     * @param _debtAmountToCover The amount of DCC tokens to burn in order to cover the user's debt.
     *
     * @notice A 10% LIQUIDATION_BONUS is received for seizing the user's funds.
     * @notice This function assumes the protocol is roughly 150% overcollateralized for effective operation.
     * @notice A known bug would occur if the protocol were only 100% collateralized, rendering liquidation impossible.
     *         For instance, if the price of the collateral plummeted before liquidation.
     */

    function liquidate(address _collateralTokenAddress, address user, uint256 _debtAmountToCover)
        external
        moreThanZeroAmount(_debtAmountToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DCCEngine__GoodHealthFactor();
        }
        if (_debtAmountToCover > s_collateralDeposited[user][_collateralTokenAddress]) {
            revert DCCEngine__ExcessDebtAmountToCover();
        }
        uint256 tokenAmountToCover = _getTokenAmountFromUsdValue(_collateralTokenAddress, _debtAmountToCover);
        // total amount to cover * (100 + bonus) / 100
        uint256 totalCollateralToRedeem =
            (tokenAmountToCover * (LIQUIDATION_BONUS + LIQUIDATION_PRECISION)) / LIQUIDATION_PRECISION;

        _burnDCC(_debtAmountToCover, user, msg.sender);
        _redeemCollateral(_collateralTokenAddress, totalCollateralToRedeem, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DCCEngine__NotImprovedHealthFactor();
        }
        _revertIfBrokenHealthFactor(msg.sender);
    }

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

    function calculateHealthFactor(uint256 totalDccMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDccMinted, collateralValueInUsd);
    }

    function _revertIfBrokenHealthFactor(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MAX_HEALTH_FACTOR) {
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

    function _getUsdValueFromTokenAmount(address _tokenAddress, uint256 _amount) private view returns (uint256) {
        CollateralInfo storage collateralInfo = s_colateralInfos[_tokenAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralInfo.priceFeed);

        (, int256 price,,,) = priceFeed.latestRoundData();
        // ex 1 ETH = 2000 USD
        // return price from chainlink priceFeed will be 2000 * 1e8
        // value = amount * price * amount precision / value precision
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return uint256(price) * PRICE_FEED_ADDITIONAL_PRECISION * _amount / DCC_PRECISION;
    }

    function _getTokenAmountFromUsdValue(address _tokenAddress, uint256 _usdValue) private view returns (uint256) {
        CollateralInfo storage collateralInfo = s_colateralInfos[_tokenAddress];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(collateralInfo.priceFeed);

        (, int256 price,,,) = priceFeed.latestRoundData();
        // ex 1 ETH = 2000 USD
        // return price from chainlink priceFeed will be 2000 * 1e8
        // value = amount * price * amount precision / value precision
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return (_usdValue * DCC_PRECISION) / (uint256(price) * PRICE_FEED_ADDITIONAL_PRECISION);
    }

    function getUsdValueFromTokenAmount(address _tokenAddress, uint256 _amount) external view returns (uint256) {
        return _getUsdValueFromTokenAmount(_tokenAddress, _amount);
    }

    function getTokenAmountFromUsdValue(address _tokenAddress, uint256 _usdValue) external view returns (uint256) {
        return _getTokenAmountFromUsdValue(_tokenAddress, _usdValue);
    }

    function getDCCAddress() external view returns (address) {
        return address(i_dcc);
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
}
