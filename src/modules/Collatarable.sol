// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { OracleLib } from "../libraries/OracleLib.sol";
import { MathLib } from "../libraries/MathLib.sol";
import { Errors } from "../libraries/Errors.sol";
import { Events } from "../libraries/Events.sol";
import { Base } from "./Base.sol";

contract Collatarable is Base {
  /*//////////////////////////////////////////////////////////////
                                 TYPES
  //////////////////////////////////////////////////////////////*/
  using OracleLib for AggregatorV3Interface;

  /*//////////////////////////////////////////////////////////////
                                 STATE
  //////////////////////////////////////////////////////////////*/
  mapping(address => address) private s_collateralOracles;
  address[] private s_collaterals;
  mapping(address => mapping(address => uint256)) s_callateralDeposited;

  modifier allowedCollateral(address _collateral) {
    if (s_collateralOracles[_collateral] == address(0)) {
      revert Errors.DSCEngine__WrongCollateral();
    }
    _;
  }

  /*//////////////////////////////////////////////////////////////
                                LOGIC
  //////////////////////////////////////////////////////////////*/
  constructor(
    address[] memory _collaterals,
    address[] memory _oracles // USD price oracles
  ) {
    if (_collaterals.length != _oracles.length) {
      revert Errors.DSCEngine__CollateralAndOraclesAddressesMustBeEqualLength();
    }

    for (uint256 i = 0; i < _collaterals.length; i++) {
      if (_collaterals[i] == address(0) || _oracles[i] == address(0)) {
        revert Errors.DSCEngine__ZeroAddress();
      }

      bool isOracleValid = AggregatorV3Interface(_oracles[i]).validateOracle();
      if (!isOracleValid) {
        revert Errors.DSCEngine__InvalidOracle();
      }

      s_collateralOracles[_collaterals[i]] = _oracles[i];
      s_collaterals.push(_collaterals[i]);
    }
  }

  /**
   * @notice follows CEI
   * @param _collateral The address of the token to deposit as collateral
   * @param _amount The amount of the token to deposit
   */
  function _depositCollateral(
    address _collateral,
    uint256 _amount
  )
    internal
    moreThanZero(_amount)
    allowedCollateral(_collateral)
  {
    s_callateralDeposited[msg.sender][_collateral] += _amount;
    emit Events.CallateralDeposited(msg.sender, _collateral, _amount);
    bool success = IERC20(_collateral).transferFrom(msg.sender, address(this), _amount);
    if (!success) {
      revert Errors.DSCEngine__TransferFailed();
    }
  }

  /**
   * This function is used to redeem collateral token from one user and transfer it to another one
   * @param _from The address of the user to redeem from
   * @param _to The address of the user to redeem to
   * @param _collateral The address of token to redeem
   * @param _amount The amount of collateral token to redeem
   */
  function _redeemCollateral(
    address _from,
    address _to,
    address _collateral,
    uint256 _amount
  )
    internal
    allowedCollateral(_collateral)
    moreThanZero(_amount)
  {
    s_callateralDeposited[_from][_collateral] -= _amount;
    emit Events.CollateralRedeemed(_from, _to, _collateral, _amount);
    bool success = IERC20(_collateral).transfer(_to, _amount);
    if (!success) {
      revert Errors.DSCEngine__TransferFailed();
    }
  }

  function _getCollateralAmountFromUsd(address _collateral, uint256 _usdAmountInWei) internal view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralOracles[_collateral]);
    (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
    return MathLib.divWithPrecision(_usdAmountInWei, MathLib.getDefaultDecimals(), uint256(price), priceFeed.decimals());
  }

  function _getAccountCollateralTokenAmount(address _user, address _collateralToken) internal view returns (uint256) {
    return s_callateralDeposited[_user][_collateralToken];
  }

  function _getAccountCallateralValueInUsd(address _user) internal view returns (uint256 totalCallateralValueInUsd) {
    for (uint256 i = 0; i < s_collaterals.length; i++) {
      address token = s_collaterals[i];
      uint256 amount = s_callateralDeposited[_user][token];
      totalCallateralValueInUsd = MathLib.add(totalCallateralValueInUsd, _getCollateralUsdValue(token, amount));
    }
  }

  function _getAccountCollateralValueInUsdExcept(address _user, address _collateral) internal view returns (uint256) {
    uint256 totalCallateralValueInUsd = 0;
    for (uint256 i = 0; i < s_collaterals.length; i++) {
      address token = s_collaterals[i];
      if (token == _collateral) {
        continue;
      }
      uint256 amount = s_callateralDeposited[_user][token];
      totalCallateralValueInUsd = MathLib.add(totalCallateralValueInUsd, _getCollateralUsdValue(token, amount));
    }
    return totalCallateralValueInUsd;
  }

  function _getCollateralUsdValue(address _collateral, uint256 _amount) internal view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralOracles[_collateral]);
    (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
    return
      MathLib.mulWithPrecision(_amount, IERC20Metadata(_collateral).decimals(), uint256(price), priceFeed.decimals());
  }

  function _getCollaterals() internal view returns (address[] memory) {
    return s_collaterals;
  }

  function _getCollateralOracle(address _collateralToken) internal view returns (address) {
    return s_collateralOracles[_collateralToken];
  }
}
