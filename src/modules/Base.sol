// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Errors } from "../libraries/Errors.sol";

contract Base {
  modifier moreThanZero(uint256 _amount) {
    if (_amount <= 0) {
      revert Errors.DSCEngine__AmountLessThanOrEqualZero();
    }
    _;
  }
}
