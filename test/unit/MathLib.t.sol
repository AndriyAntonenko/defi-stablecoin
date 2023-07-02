// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { MathLib } from "../../src/libraries/MathLib.sol";

contract MathLibTest is Test {
  function setUp() public { }

  function testMulWithPrecisionWithDifferentPrecisions() public {
    uint256 aDec = 18;
    uint256 a = 4 * 10 ** aDec;
    uint256 bDec = 8;
    uint256 b = 2 * 10 ** bDec;
    uint256 expected = 8 * MathLib.getDefaultPrecision();
    uint256 actual = MathLib.mulWithPrecision(a, aDec, b, bDec);
    assertEq(actual, expected);
  }

  function testMulWithPrecisionWithSamePrecision() public {
    uint256 aDec = 8;
    uint256 a = 4 * 10 ** aDec;
    uint256 bDec = 8;
    uint256 b = 2 * 10 ** bDec;
    uint256 expected = 8 * MathLib.getDefaultPrecision();
    uint256 actual = MathLib.mulWithPrecision(a, aDec, b, bDec);
    assertEq(actual, expected);
  }

  function testDivWithPrecisionWithGreaterNumeratorPrecisions() public {
    uint256 aDec = 18;
    uint256 a = 4 * 10 ** aDec;
    uint256 bDec = 8;
    uint256 b = 2 * 10 ** bDec;
    uint256 expected = 2 * MathLib.getDefaultPrecision();
    uint256 actual = MathLib.divWithPrecision(a, aDec, b, bDec);
    assertEq(actual, expected);
  }

  function testDivWithPrecisionWithGreaterDenominatorPrecisions() public {
    uint256 aDec = 10;
    uint256 a = 4 * 10 ** aDec;
    uint256 bDec = 18;
    uint256 b = 2 * 10 ** bDec;
    uint256 expected = 2 * MathLib.getDefaultPrecision();
    uint256 actual = MathLib.divWithPrecision(a, aDec, b, bDec);
    assertEq(actual, expected);
  }

  function testDivWithPrecisionWithSamePrecision() public {
    uint256 aDec = 10;
    uint256 a = 4 * 10 ** aDec;
    uint256 bDec = 10;
    uint256 b = 2 * 10 ** bDec;
    uint256 expected = 2 * MathLib.getDefaultPrecision();
    uint256 actual = MathLib.divWithPrecision(a, aDec, b, bDec);
    assertEq(actual, expected);
  }
}
