// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract CommonModifiers {
  modifier moreThanZero(uint256 _amount) {
    if (_amount <= 0) {
      revert("CommonModifiers::moreThanZero: AMOUNT_MUST_BE_MORE_THAN_ZERO");
    }
    _;
  }
}
