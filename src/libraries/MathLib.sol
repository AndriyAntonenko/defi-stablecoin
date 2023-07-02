// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library MathLib {
  uint256 internal constant MAX_DECIMALS = 18;
  uint256 internal constant PRECISION = 1e18;

  function mulWithPrecision(uint256 a, uint256 aDec, uint256 b, uint256 bDec) internal pure returns (uint256) {
    require(aDec <= MAX_DECIMALS && bDec <= MAX_DECIMALS, "MathLib::mulWithPrecision: DECIMALS_OVERFLOW");
    uint256 aMulB = mul(a, b);
    uint256 aMulBDec = add(aDec, bDec);

    if (aMulBDec < MAX_DECIMALS) {
      // if multiplication decimals is less then max decimals, then we should add decimals
      return mul(aMulB, div(PRECISION, pow(10, aMulBDec)));
    }
    // if multiplication decimals is more then max decimals, then we should sub decimals
    return div(aMulB, pow(10, sub(aMulBDec, MAX_DECIMALS)));
  }

  function divWithPrecision(uint256 a, uint256 aDec, uint256 b, uint256 bDec) internal pure returns (uint256) {
    require(aDec <= MAX_DECIMALS && bDec <= MAX_DECIMALS, "MathLib::divWithPrecision: DECIMALS_OVERFLOW");
    if (aDec > bDec) {
      return div(mul(a, PRECISION), mul(b, pow(10, sub(aDec, bDec))));
    }
    return div(mul(a, mul(PRECISION, pow(10, sub(bDec, aDec)))), b);
  }

  function getDefaultDecimals() internal pure returns (uint256) {
    return MAX_DECIMALS;
  }

  function getDefaultPrecision() internal pure returns (uint256) {
    return PRECISION;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      uint256 c = a + b;
      if (c < a) revert("MathLib::add: OVERFLOW");
      return c;
    }
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      if (b > a) revert("MathLib::sub: UNDERFLOW");
      return a - b;
    }
  }

  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      if (a == 0) return 0;
      uint256 c = a * b;
      if (c / a != b) revert("MathLib::mul: OVERFLOW");
      return c;
    }
  }

  function pow(uint256 a, uint256 b) internal pure returns (uint256 c) {
    unchecked {
      if (a == 0) return 0;
      if (b == 0) return 1;
      c = a ** b;
      if (c < a) revert("MathLib::pow: OVERFLOW");
    }
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      if (b == 0) revert("MathLib::div: DIVISION_BY_ZERO");
      return a / b;
    }
  }
}
