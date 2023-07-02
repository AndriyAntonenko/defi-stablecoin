// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DeployDSC } from "../../scripts/DeployDSC.s.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../scripts/HelperConfig.s.sol";
import { Handler } from "./Handler.t.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract InvariantsTest is StdInvariant, Test {
  using console for *;

  DeployDSC deployer;
  DSCEngine engine;
  DecentralizedStableCoin dsc;
  HelperConfig config;
  address weth;
  address wbtc;
  Handler handler;

  function setUp() external {
    deployer = new DeployDSC();
    (dsc, engine, config) = deployer.run();
    (,, weth, wbtc,) = config.activeNetworkConfig();
    handler = new Handler(engine, dsc);
    targetContract(address(handler));
  }

  function invariant_MintedDscAlwaysLessThanCollateralTokensValue() external {
    uint256 dscTotalSupply = dsc.totalSupply();
    uint256 wethCollateral = ERC20Mock(weth).balanceOf(address(engine));
    uint256 wbtcCollateral = ERC20Mock(wbtc).balanceOf(address(engine));

    uint256 wethUsdValue = engine.getCollateralUsdValue(weth, wethCollateral);
    uint256 wbtcUsdValue = engine.getCollateralUsdValue(wbtc, wbtcCollateral);

    console.log("dscTotalSupply", dscTotalSupply);
    console.log("wethUsdValue", wethUsdValue);
    console.log("wbtcUsdValue", wbtcUsdValue);
    console.log("Times mint called", handler.timesMintIsCalled());

    assertTrue(
      dscTotalSupply <= wethUsdValue + wbtcUsdValue,
      "Invariant broken: Minted DSC always less than collateral tokens value"
    );
  }
}
