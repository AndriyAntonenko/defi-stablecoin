// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author Andriy Antonenko
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == 1 USD.
 * This stablecoin has the propeties:
 * - Exogenous Callteral
 * - Algorithmically Stable
 * - USD Pegged
 *
 * System should always be "overcollateralized".
 * At no point, should the value of all callateral be less than the backed USD value of all DSC.
 *
 * @notice This contract is the core of DSC system, It handles all the logic for mining and redeeming DSC,
 * as well as depositing & withdrawing collateral.
 *
 * @notice This contract is VERY loosely based on the MakerDAO DSS
 */
contract DSCEngine is ReentrancyGuard {
  /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
  error DSCEngine__AmountMustBeMoreThanZero();
  error DSCEngine__TokenNotAllowedAsCollateral();
  error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength();
  error DSCEngine__ZeroAddress();
  error DSCEngine__TransferFailed();
  error DSCEngine__BreaksHealthFactor();
  error DSCEngine__MintFailed();

  /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/
  uint256 private constant ADDITIAONAL_FEED_PRECISION = 1e10;
  uint256 private constant PRECISION = 1e18;

  // LIQUIDATION CONDITION: collateral >= dscAmount * LIQUIDATION_PRECISION / LIQUIDATION_THRESHOLD
  uint256 private constant LIQUIDATION_THRESHOLD = 50; // 150% overcollateralized
  uint256 private constant LIQUIDATION_PRECISION = 100;

  uint256 private constant MIN_HEALTH_FACTOR = 1;

  mapping(address => address) private s_priceFeeds;
  mapping(address => mapping(address => uint256)) private s_callateralDeposited; // user => token => deposited
  mapping(address => uint256) private s_dscMinted; // user => amount
  DecentralizedStableCoin private immutable i_dsc;

  address[] private s_callateralTokens;

  /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
  event CallateralDeposited(address indexed user, address indexed token, uint256 amount);

  /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

  modifier moreThanZero(uint256 _amount) {
    if (_amount <= 0) {
      revert DSCEngine__AmountMustBeMoreThanZero();
    }
    _;
  }

  modifier allowedToken(address _token) {
    if (s_priceFeeds[_token] == address(0)) {
      revert DSCEngine__TokenNotAllowedAsCollateral();
    }
    _;
  }

  /*//////////////////////////////////////////////////////////////
                                 LOGIC
    //////////////////////////////////////////////////////////////*/

  constructor(
    address[] memory tokenAddresses,
    address[] memory priceFeedAddresses, // USD price feeds
    address dscAddress
  ) {
    if (tokenAddresses.length != priceFeedAddresses.length) {
      revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength();
    }

    if (dscAddress == address(0)) {
      revert DSCEngine__ZeroAddress();
    }

    i_dsc = DecentralizedStableCoin(dscAddress);
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      if (tokenAddresses[i] == address(0) || priceFeedAddresses[i] == address(0)) {
        revert DSCEngine__ZeroAddress();
      }
      s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
      s_callateralTokens.push(tokenAddresses[i]);
    }
  }

  /**
   *
   * @param _collateralToken The address of the token to deposit as collateral
   * @param _amountCollateral The amount of the token to deposit
   * @param _amountDscToMint The amount of DSC to mint
   * @notice this function will deposit your collateral and mint DSC in one transaction
   */
  function depositCollateralAndMintDsc(
    address _collateralToken,
    uint256 _amountCollateral,
    uint256 _amountDscToMint
  )
    external
  {
    depositCollateral(_collateralToken, _amountCollateral);
    mintDsc(_amountDscToMint);
  }

  /**
   * @notice follows CEI
   * @param _token The address of the token to deposit as collateral
   * @param _amount The amount of the token to deposit
   */
  function depositCollateral(
    address _token,
    uint256 _amount
  )
    public
    moreThanZero(_amount)
    nonReentrant
    allowedToken(_token)
  {
    s_callateralDeposited[msg.sender][_token] += _amount;
    emit CallateralDeposited(msg.sender, _token, _amount);
    bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
    if (!success) {
      revert DSCEngine__TransferFailed();
    }
  }

  function redeemCollateral() external { }

  /**
   * @notice follow CEI
   * @param _dscAmount amount of decentrilized stable coin to mint
   * @notice they must have more collateral valuie than minimum threshold
   */
  function mintDsc(uint256 _dscAmount) public moreThanZero(_dscAmount) nonReentrant {
    s_dscMinted[msg.sender] += _dscAmount;
    _revertIfHealthFactorIsBroken(msg.sender);
    bool minted = i_dsc.mint(msg.sender, _dscAmount);
    if (!minted) {
      revert DSCEngine__MintFailed();
    }
  }

  function redeemCollateralForDsc() external { }

  function burnDsc() external { }

  function liquidate() external { }

  function getHealthFactor() external view { }

  /*//////////////////////////////////////////////////////////////
                  INTERNAL & PRIVATE VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function _getAccountInfo(address _user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
    totalDscMinted = s_dscMinted[_user];
    collateralValueInUsd = getAccountCallateralValueInUsd(_user);
  }

  /**
   * Returns how close to liquidation a user isasd
   * If user goes bellow 1, then thay can get liquidated
   * @param _user address of the user
   */
  function _healthFactor(address _user) internal view returns (uint256) {
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInfo(_user);
    uint256 collateralAdjustedForThreshold = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION;
    return collateralAdjustedForThreshold * PRECISION / totalDscMinted;
  }

  function _revertIfHealthFactorIsBroken(address user) internal view {
    if (_healthFactor(user) < MIN_HEALTH_FACTOR) {
      revert DSCEngine__BreaksHealthFactor();
    }
  }

  /*//////////////////////////////////////////////////////////////
                  PUBLIC & EXTERNAL VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  function getAccountCallateralValueInUsd(address _user) public view returns (uint256 totalCallateralValueInUsd) {
    for (uint256 i = 0; i < s_callateralTokens.length; i++) {
      address token = s_callateralTokens[i];
      uint256 amount = s_callateralDeposited[_user][token];
      totalCallateralValueInUsd += getUsdValue(token, amount);
    }
  }

  function getUsdValue(address token, uint256 amount) public view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price,,,) = priceFeed.latestRoundData();
    return uint256(price) * amount * ADDITIAONAL_FEED_PRECISION / PRECISION;
  }
}
