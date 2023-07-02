// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Events {
  event CallateralDeposited(address indexed user, address indexed token, uint256 amount);
  event CollateralRedeemed(
    address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
  );
  event Liquidated(
    address indexed liquidator,
    address indexed liquidated,
    address indexed collateralToken,
    uint256 redeemed,
    uint256 burned,
    uint256 initialHealthFactor,
    uint256 finalHealthFactor
  );
}
