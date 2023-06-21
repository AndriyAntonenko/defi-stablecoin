// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
  using console for *;

  DSCEngine engine;
  DecentralizedStableCoin dsc;

  ERC20Mock weth;
  ERC20Mock wbtc;
  MockV3Aggregator ethUsdPriceFeed;
  uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
  uint256 public timesMintIsCalled;

  address[] public actors;
  address internal currentActor;

  constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
    engine = _dscEngine;
    dsc = _dsc;

    address[] memory collateralTokens = engine.getCollateralTokens();
    weth = ERC20Mock(collateralTokens[0]);
    wbtc = ERC20Mock(collateralTokens[1]);
    ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralPriceFeed(collateralTokens[0]));

    // setup actors
    actors = new address[](3);
    actors[0] = address(0x1);
    actors[1] = address(0x2);
    actors[2] = address(0x3);
  }

  modifier useActor(uint256 actorIndexSeed) {
    currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
    vm.startPrank(currentActor);
    _;
    vm.stopPrank();
  }

  function depositCollateral(
    uint256 _actorIndexSeed,
    uint256 _collateralSeed,
    uint256 _amountCollateral
  )
    public
    useActor(_actorIndexSeed)
  {
    _amountCollateral = bound(_amountCollateral, 1, MAX_DEPOSIT_SIZE);
    ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);

    collateral.mint(currentActor, _amountCollateral);
    collateral.approve(address(engine), _amountCollateral);
    engine.depositCollateral(address(collateral), _amountCollateral);
  }

  function redeemCollateral(
    uint256 _actorIndexSeed,
    uint256 _collateralSeed,
    uint256 _amountCollateral
  )
    public
    useActor(_actorIndexSeed)
  {
    ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
    uint256 maxCollateralToRedeem = engine.estimateAccountOverheadCollateral(currentActor, address(collateral));
    _amountCollateral = bound(_amountCollateral, 0, maxCollateralToRedeem);
    if (_amountCollateral == 0) {
      return;
    }
    engine.redeemCollateral(address(collateral), _amountCollateral);
  }

  function mintDsc(uint256 _actorIndexSeed, uint256 _amount) public useActor(_actorIndexSeed) {
    uint256 maxDscToMint = engine.estimateAccountMaxMintableDsc(currentActor);
    _amount = bound(_amount, 0, maxDscToMint);
    if (_amount == 0) {
      return;
    }

    engine.mintDsc(_amount);
    timesMintIsCalled++;
  }

  // Helper functions
  function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
    if (collateralSeed % 2 == 0) {
      return weth;
    } else {
      return wbtc;
    }
  }
}
