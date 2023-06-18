// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../scripts/DeployDSC.s.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../scripts/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
  DeployDSC public deployer;
  DecentralizedStableCoin public dsc;
  DSCEngine public engine;
  HelperConfig public config;
  address ethUsdPriceFeed;
  address weth;

  address public immutable USER = makeAddr("user");
  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

  function setUp() public {
    deployer = new DeployDSC();
    (dsc, engine, config) = deployer.run();
    (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
    ERC20Mock(weth).mint(address(this), STARTING_ERC20_BALANCE);
  }

  /*//////////////////////////////////////////////////////////////
                             PRICE TESTS
  //////////////////////////////////////////////////////////////*/

  function testGetUsdValue() public {
    uint256 ethAmount = 15e18;
    uint256 expectedUsd = 30_000e18;
    uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    assertEq(actualUsd, expectedUsd);
  }

  /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
  //////////////////////////////////////////////////////////////*/
  function testRevertIfCollateralZero() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
    engine.depositCollateral(weth, 0);
    vm.stopPrank();
  }
}
