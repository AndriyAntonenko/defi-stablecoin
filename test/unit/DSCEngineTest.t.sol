// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../scripts/DeployDSC.s.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../scripts/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
  /*//////////////////////////////////////////////////////////////
                              MOCKS
  //////////////////////////////////////////////////////////////*/
  event CallateralDeposited(address indexed user, address indexed token, uint256 amount);

  DeployDSC public deployer;
  DecentralizedStableCoin public dsc;
  DSCEngine public engine;
  HelperConfig public config;
  address ethUsdPriceFeed;
  address weth;

  address public immutable USER = makeAddr("user");
  uint256 public constant AMOUNT_COLLATERAL = 2 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
  uint256 public constant AMOUNT_MINT = 100e18;

  function setUp() public {
    deployer = new DeployDSC();
    (dsc, engine, config) = deployer.run();
    (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
    ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
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

  function testRevertIfTokenNotAllowedToDepositCollateral() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowedAsCollateral.selector);
    engine.depositCollateral(address(dsc), AMOUNT_COLLATERAL);
    vm.stopPrank();
  }

  function testCollateralDepositedEventEmit() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    vm.expectEmit(true, true, false, true, address(engine));
    emit CallateralDeposited(USER, weth, AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
  }

  function testCollateralValueInUsdIsCorrect() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();

    uint256 callateralValueInUsd = engine.getAccountCallateralValueInUsd(USER);
    uint256 expectedCallateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
    assertEq(callateralValueInUsd, expectedCallateralValueInUsd);
  }

  /*//////////////////////////////////////////////////////////////
                        MINT DSC TESTS
  //////////////////////////////////////////////////////////////*/
  function testRevertIfMintAmountZero() public {
    vm.startPrank(USER);
    vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
    engine.mintDsc(0);
    vm.stopPrank();
  }

  function testRevertMintIfHealthFactorIsBroken() public {
    vm.startPrank(USER);
    vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
    engine.mintDsc(AMOUNT_MINT);
    vm.stopPrank();
  }

  function testSuccessfullMint() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();

    vm.startPrank(USER);
    engine.mintDsc(AMOUNT_MINT);
    vm.stopPrank();

    uint256 dscBalance = dsc.balanceOf(USER);
    assertEq(dscBalance, AMOUNT_MINT);
  }
}
