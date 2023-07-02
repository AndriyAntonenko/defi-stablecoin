// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Errors {
  /*//////////////////////////////////////////////////////////////
                                ENGINE
  //////////////////////////////////////////////////////////////*/
  error DSCEngine__WrongCollateral();
  error DSCEngine__CollateralAndOraclesAddressesMustBeEqualLength();
  error DSCEngine__ZeroAddress();
  error DSCEngine__InvalidOracle();
  error DSCEngine__TransferFailed();
  error DSCEngine__BreaksHealthFactor();
  error DSCEngine__MintFailed();
  error DSCEngine__HealthFactorOk();
  error DSCEngine__HealthFactorNotImproved();
  error DSCEngine__AmountLessThanOrEqualZero();

  /*//////////////////////////////////////////////////////////////
                                ERC20
  //////////////////////////////////////////////////////////////*/
  error DecentralizedStableCoin__MustBeMoreThanZero();
  error DecentralizedStableCoin__BurnAmountExceedsBalance();
  error DecentralizedStableCoin__ZeroAddress();
}
