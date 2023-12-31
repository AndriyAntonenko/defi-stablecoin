// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { OracleLib } from "./libraries/OracleLib.sol";
import { Errors } from "./libraries/Errors.sol";
import { Events } from "./libraries/Events.sol";

import { Collatarable } from "./modules/Collatarable.sol";
import { Base } from "./modules/Base.sol";

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
contract DSCEngine is Base, ReentrancyGuard, Collatarable {
  /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/
  uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
  uint256 private constant PRECISION = 1e18;

  // LIQUIDATION CONDITION: collateral < dscAmount * LIQUIDATION_PRECISION / LIQUIDATION_THRESHOLD
  uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
  uint256 private constant LIQUIDATION_PRECISION = 100;

  uint256 private constant MIN_HEALTH_FACTOR = 1e18;

  uint256 private constant LIQUIDATION_BONUS = 5; // 5% bonus for liquidating

  mapping(address => uint256) private s_dscMinted; // user => amount
  DecentralizedStableCoin private immutable i_dsc;

  /*//////////////////////////////////////////////////////////////
                                 LOGIC
  //////////////////////////////////////////////////////////////*/

  constructor(
    address[] memory _collaterals,
    address[] memory _oracles, // USD price oracles
    address dscAddress
  )
    Collatarable(_collaterals, _oracles)
  {
    if (dscAddress == address(0)) {
      revert Errors.DSCEngine__ZeroAddress();
    }
    i_dsc = DecentralizedStableCoin(dscAddress);
  }

  /**
   *
   * @param _collateral The address of the token to deposit as collateral
   * @param _amountCollateral The amount of the token to deposit
   * @param _amountDscToMint The amount of DSC to mint
   * @notice this function will deposit your collateral and mint DSC in one transaction
   */
  function depositCollateralAndMintDsc(
    address _collateral,
    uint256 _amountCollateral,
    uint256 _amountDscToMint
  )
    external
  {
    depositCollateral(_collateral, _amountCollateral);
    mintDsc(_amountDscToMint);
  }

  /**
   * @notice follows CEI
   * @param _collateral The address of the token to deposit as collateral
   * @param _amount The amount of the token to deposit
   */
  function depositCollateral(address _collateral, uint256 _amount) public nonReentrant {
    _depositCollateral(_collateral, _amount);
  }

  /**
   * This function will redeem collateral from the msg.sender and transfer it to msg.sender back
   * @notice This function shouldn't break health factor, but if it will, then revert will happend
   * @notice CEI: Check, Effects, Interactions
   * @param _collateral The address of token to redeem
   * @param _amount The amount of collateral token to redeem
   */
  function redeemCollateral(address _collateral, uint256 _amount) public nonReentrant {
    _redeemCollateral(msg.sender, msg.sender, _collateral, _amount);
    _revertIfHealthFactorIsBroken(msg.sender);
  }

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
      revert Errors.DSCEngine__MintFailed();
    }
  }

  /**
   * @param _tokenCollateralAddress The address of the token to redeem
   * @param _amountCollateral The amount of the token to redeem
   * @param _amountDscToBurn The amount of DSC to burn
   * This function burns DSC and redeems underlying collateral in one transaction
   */
  function redeemCollateralForDsc(
    address _tokenCollateralAddress,
    uint256 _amountCollateral,
    uint256 _amountDscToBurn
  )
    external
  {
    burnDsc(_amountDscToBurn);
    redeemCollateral(_tokenCollateralAddress, _amountCollateral);
  }

  function burnDsc(uint256 _amount) public moreThanZero(_amount) {
    _burnDsc(msg.sender, msg.sender, _amount);
    _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
  }

  /**
   * @param _collateral The address of the token to liquidate from the user
   * @param _user The user who has broken the health factor
   * @param _debtToCover The amount of DSC to burn to improve the users health factor
   * @notice You can partially liquidate a user
   * @notice You will get a liquidation reward for taking user funds
   * @notice This function working assumes the protocol 20% overcollateralized
   */
  function liquidate(
    address _collateral,
    address _user,
    uint256 _debtToCover
  )
    external
    moreThanZero(_debtToCover)
    nonReentrant
  {
    uint256 startingUserHealthFactor = _healthFactor(_user);
    if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
      revert Errors.DSCEngine__HealthFactorOk();
    }
    (,, uint256 totalCollateralToRedeem) = estimateLiquidationProfit(_collateral, _debtToCover);
    // take collateral from "bad" user and transfer it to liquidator (with bonus)
    _redeemCollateral(_user, msg.sender, _collateral, totalCollateralToRedeem);
    // burn DSC for liquidator and take away minted DSC from _user
    _burnDsc(msg.sender, _user, _debtToCover);

    uint256 endingUserHealthFactor = _healthFactor(_user);

    if (endingUserHealthFactor <= startingUserHealthFactor) {
      revert Errors.DSCEngine__HealthFactorNotImproved();
    }
    _revertIfHealthFactorIsBroken(msg.sender);

    emit Events.Liquidated(
      msg.sender,
      _user,
      _collateral,
      totalCollateralToRedeem,
      _debtToCover,
      startingUserHealthFactor,
      endingUserHealthFactor
      );
  }

  /*//////////////////////////////////////////////////////////////
                  INTERNAL & PRIVATE VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @dev Low-level internal function, do not call unles the function calling it is checking for health factors being
   * broken
   * @param _from The address of the user to actually burn from. His tokens will be transfered to address(this) and then
   * burned
   * @param _onBehalfOf The address of the user to burn on behalf of. This is the user who will have their minted DSC
   * burned
   * @param _amount The amount of DSC to burn
   */
  function _burnDsc(address _from, address _onBehalfOf, uint256 _amount) internal {
    s_dscMinted[_onBehalfOf] -= _amount;
    bool success = i_dsc.transferFrom(_from, address(this), _amount);
    if (!success) {
      revert Errors.DSCEngine__TransferFailed();
    }
    i_dsc.burn(_amount);
  }

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
    // collateral / (2*dscMinted)
    // >= 1 = healthy
    // < 1 = unhealthy -> liquidate
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInfo(_user);
    if (totalDscMinted == 0) {
      return type(uint256).max; // if no DSC minted, then health factor ok
    }
    uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
  }

  function _revertIfHealthFactorIsBroken(address user) internal view {
    if (_healthFactor(user) < MIN_HEALTH_FACTOR) {
      revert Errors.DSCEngine__BreaksHealthFactor();
    }
  }

  function _calculateMaxMintableDsc(address _user) internal view returns (uint256) {
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInfo(_user);
    uint256 maxMintableDsc = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    uint256 mintableDsc = maxMintableDsc - totalDscMinted;
    return mintableDsc;
  }

  /*//////////////////////////////////////////////////////////////
                  PUBLIC & EXTERNAL VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  function getCollateralAmountFromUsd(address _collateral, uint256 _usdAmountInWei) public view returns (uint256) {
    return _getCollateralAmountFromUsd(_collateral, _usdAmountInWei);
  }

  function getAccountCallateralValueInUsd(address _user) public view returns (uint256) {
    return _getAccountCallateralValueInUsd(_user);
  }

  function getCollateralUsdValue(address _collateral, uint256 amount) public view returns (uint256) {
    return _getCollateralUsdValue(_collateral, amount);
  }

  function getAccountInfo(address _user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
    return _getAccountInfo(_user);
  }

  function getAccountHealthFactor(address _user) external view returns (uint256) {
    return _healthFactor(_user);
  }

  function getAccountCollateralTokenAmount(address _user, address _collateral) external view returns (uint256) {
    return _getAccountCollateralTokenAmount(_user, _collateral);
  }

  function estimateLiquidationProfit(
    address _collateral,
    uint256 _debtToCover
  )
    public
    view
    returns (uint256 tokenAmountFromDebtCovered, uint256 bonusCollateral, uint256 totalCollateralToRedeem)
  {
    // convert debt to cover to collateral token amount
    tokenAmountFromDebtCovered = _getCollateralAmountFromUsd(_collateral, _debtToCover);
    // get bonus collateral to reward liquidator
    bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
    // get total collateral to redeem
    totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
  }

  function estimateAccountMaxMintableDsc(address _user) external view returns (uint256) {
    return _calculateMaxMintableDsc(_user);
  }

  function estimateAccountOverheadCollateral(address _user, address _collateralToken) external view returns (uint256) {
    uint256 usdCollateralOverhead = _calculateMaxMintableDsc(_user) * LIQUIDATION_PRECISION / LIQUIDATION_THRESHOLD;
    uint256 _overheadInCollateralTokenValue = _getCollateralAmountFromUsd(_collateralToken, usdCollateralOverhead);

    uint256 _currentCollateralTokenAmount = s_callateralDeposited[_user][_collateralToken];
    if (_overheadInCollateralTokenValue > _currentCollateralTokenAmount) {
      return _currentCollateralTokenAmount;
    }
    return _overheadInCollateralTokenValue;
  }

  /**
   * This function helps to estimate liquidation price for collateral token
   * @notice if user's health factor is less than 1, then estimate returns 0
   * @notice in case, if liquidation price is 0, then user can't be liquidated
   * @param _collateral collateral token address
   * @param _user depositor
   */
  function estimateLiquidationPriceForCollateralToken(
    address _collateral,
    address _user
  )
    external
    view
    returns (int256)
  {
    uint256 userHealthFactor = _healthFactor(_user);
    if (userHealthFactor < MIN_HEALTH_FACTOR) {
      return 0;
    }
    // reversed health factor coef: LIQUIDATION_PRECISION / LIQUIDATION_THRESHOLD. It's 2
    // HF = minHF - 1
    // HF = usdCollateral / (2 * dscMinted)
    // usdCollateral = sum(t1*p1 + t2*p2 + ... + tn*pn)
    // HF = sum(t1*p1 + t2*p2 + ... + tn*pn) / (2 * dscMinted)
    // pn = (2 * HF * dscMinted - t1 * p1 - t2 * p2 - ... - tn-1 * pn-1) / tn

    uint256 currentCollateralDeposited = s_callateralDeposited[_user][_collateral];
    if (currentCollateralDeposited == 0) {
      return 0;
    }

    uint256 restCollateralValueInUsd = _getAccountCollateralValueInUsdExcept(_user, _collateral);
    uint256 totalDscMinted = s_dscMinted[_user];
    uint256 estimate = LIQUIDATION_PRECISION * (MIN_HEALTH_FACTOR - 1) * totalDscMinted;
    estimate = estimate / (LIQUIDATION_THRESHOLD);
    estimate = estimate - restCollateralValueInUsd * PRECISION;
    estimate = estimate / (currentCollateralDeposited * ADDITIONAL_FEED_PRECISION);
    return int256(estimate);
  }

  function getCollaterals() external view returns (address[] memory) {
    return _getCollaterals();
  }

  function getCollateralOracle(address _collateral) external view returns (address) {
    return _getCollateralOracle(_collateral);
  }

  function getLiquidationThreshold() external pure returns (uint256) {
    return LIQUIDATION_THRESHOLD;
  }

  function getLiquidationPrecision() external pure returns (uint256) {
    return LIQUIDATION_PRECISION;
  }

  function getPresicion() external pure returns (uint256) {
    return PRECISION;
  }

  function getAdditionalFeedPrecision() external pure returns (uint256) {
    return ADDITIONAL_FEED_PRECISION;
  }
}
