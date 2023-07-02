// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Errors } from "./libraries/Errors.sol";

/**
 * @title DecentralizedStableCoin
 * @author Andriy Antonenko
 * Callteral: Exogenous (wETH & wBTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract meant to be governed by DSCEngine.
 * This contract is just the ERC20 implementation of our stablecoin system.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
  constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) { }

  function burn(uint256 _amount) public override onlyOwner {
    uint256 balance = balanceOf(msg.sender);
    if (_amount <= 0) {
      revert Errors.DecentralizedStableCoin__MustBeMoreThanZero();
    }
    if (_amount > balance) {
      revert Errors.DecentralizedStableCoin__MustBeMoreThanZero();
    }

    super.burn(_amount);
  }

  function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
    if (_to == address(0)) {
      revert Errors.DecentralizedStableCoin__MustBeMoreThanZero();
    }
    if (_amount <= 0) {
      revert Errors.DecentralizedStableCoin__MustBeMoreThanZero();
    }
    _mint(_to, _amount);
    return true;
  }
}
