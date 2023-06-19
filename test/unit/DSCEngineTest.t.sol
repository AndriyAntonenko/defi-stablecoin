// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../scripts/DeployDSC.s.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { HelperConfig } from "../../scripts/HelperConfig.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

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
  address btcUsdPriceFeed;
  address weth;

  address public immutable USER = makeAddr("user");
  address public immutable LIQUIDATOR = makeAddr("liquidator");

  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant AMOUNT_TO_COVER = 20 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
  uint256 public constant AMOUNT_MINT = 100 ether;
  uint256 public constant BURN_AMOUNT = 50 ether;
  uint256 public constant REDEEM_COLLATERAL = 0.01 ether;
  int256 public constant LIQUIDATION_PRICE = 15e8;

  function setUp() public {
    deployer = new DeployDSC();
    (dsc, engine, config) = deployer.run();
    (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
    ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
  }

  /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
  //////////////////////////////////////////////////////////////*/
  address[] public tokenAddresses;
  address[] public feedAddresses;

  function testRevertIfTokensLengthDoesntMathPriceFeeds() public {
    tokenAddresses.push(weth);
    feedAddresses.push(ethUsdPriceFeed);
    feedAddresses.push(btcUsdPriceFeed);
    vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqualLength.selector);
    new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
  }

  function testRevertIfDscAddressIsZero() public {
    tokenAddresses.push(weth);
    feedAddresses.push(ethUsdPriceFeed);
    vm.expectRevert(DSCEngine.DSCEngine__ZeroAddress.selector);
    new DSCEngine(tokenAddresses, feedAddresses, address(0));
  }

  function testRevertIfCollateralTokenIsZero() public {
    tokenAddresses.push(address(0));
    feedAddresses.push(ethUsdPriceFeed);
    vm.expectRevert(DSCEngine.DSCEngine__ZeroAddress.selector);
    new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
  }

  function testRevertIfPriceFeedIsZero() public {
    tokenAddresses.push(weth);
    feedAddresses.push(address(0));
    vm.expectRevert(DSCEngine.DSCEngine__ZeroAddress.selector);
    new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
  }

  /*//////////////////////////////////////////////////////////////
                             PRICE TESTS
  //////////////////////////////////////////////////////////////*/

  // @TODO: make it agnostic
  function testGetUsdValue() public {
    uint256 ethAmount = 15e18;
    uint256 expectedUsd = 30_000e18;
    uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    assertEq(actualUsd, expectedUsd);
  }

  // @TODO: make it agnostic
  function testGetTokenAmountFromUsd() public {
    uint256 usdAmount = 100e18;
    // assume that price = 2000$ for 1 ETH (check helper config)
    uint256 expectedWeth = 5e16;
    uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
    assertEq(actualWeth, expectedWeth);
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

  // This is helper function to make sure that all states are correct after deposit and mint
  function _verifyDepositAndMintResult() private {
    (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInfo(USER);
    uint256 actualCollateralAmount = engine.getAccountCollateralTokenAmount(USER, weth);
    uint256 dscERC20Balance = dsc.balanceOf(USER);

    assertEq(actualCollateralAmount, AMOUNT_COLLATERAL); // check collateral amount
    assertEq(totalDscMinted, AMOUNT_MINT); // check minted amount
    assertEq(totalDscMinted, dscERC20Balance); // check minted amount to be equal to dsc balance
    assertEq(collateralValueInUsd, engine.getUsdValue(weth, AMOUNT_COLLATERAL)); // check usd equivalent of collateral
  }

  function testSuccessfullMint() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    engine.mintDsc(AMOUNT_MINT);
    vm.stopPrank();
    _verifyDepositAndMintResult();
  }

  function testDepositCollateralAndMintDsc() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
    vm.stopPrank();
    _verifyDepositAndMintResult();
  }

  /*//////////////////////////////////////////////////////////////
                        TEST HEALTH FACTOR
  //////////////////////////////////////////////////////////////*/

  function testNoDepositHealthFactor() public {
    uint256 healthFactor = engine.getAccountHealthFactor(USER);
    assertEq(healthFactor, type(uint256).max);
  }

  /*//////////////////////////////////////////////////////////////
                TEST REDEEMING AND BURNING COLLATERAL
  //////////////////////////////////////////////////////////////*/

  function testRedeemCollateral() public {
    // deposit collateral firstly
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);

    uint256 wethBalanceBeforeRedeem = ERC20Mock(weth).balanceOf(USER);
    uint256 collateralBeforeRedeem = engine.getAccountCollateralTokenAmount(USER, weth);

    // redeem collateral
    engine.redeemCollateral(weth, REDEEM_COLLATERAL);

    uint256 wethBalanceAfterRedeem = ERC20Mock(weth).balanceOf(USER);
    uint256 collateralAfterRedeem = engine.getAccountCollateralTokenAmount(USER, weth);

    assertEq(wethBalanceAfterRedeem, wethBalanceBeforeRedeem + REDEEM_COLLATERAL);
    assertEq(collateralAfterRedeem, collateralBeforeRedeem - REDEEM_COLLATERAL);
  }

  function testRevertRedeemCollateralIfHealthFactorIsBroken() public {
    // deposit + mint firstly
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);

    vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
    engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
  }

  function testBurnDsc() public {
    // deposit + mint firstly
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);

    uint256 dscBalanceBeforeBurn = dsc.balanceOf(USER);
    uint256 dscTotalSupplyBeforeBurn = dsc.totalSupply();
    (uint256 dscMintedBeforBurn,) = engine.getAccountInfo(USER);

    // burn dsc
    dsc.approve(address(engine), BURN_AMOUNT); // don't forget to approve engine to transfer your dsc
    engine.burnDsc(BURN_AMOUNT);

    uint256 dscBalanceAfterBurn = dsc.balanceOf(USER);
    uint256 dscTotalSupplyAfterBurn = dsc.totalSupply();
    (uint256 dscMintedAfterBurn,) = engine.getAccountInfo(USER);

    assertEq(dscBalanceAfterBurn, dscBalanceBeforeBurn - BURN_AMOUNT);
    assertEq(dscTotalSupplyAfterBurn, dscTotalSupplyBeforeBurn - BURN_AMOUNT);
    assertEq(dscMintedAfterBurn, dscMintedBeforBurn - BURN_AMOUNT);
  }

  function testRedeemCollateralForDsc() public {
    // deposit + mint firstly
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);

    uint256 dscBalanceBeforeBurn = dsc.balanceOf(USER);
    uint256 dscTotalSupplyBeforeBurn = dsc.totalSupply();
    (uint256 dscMintedBeforBurn,) = engine.getAccountInfo(USER);
    uint256 wethBalanceBeforeRedeem = ERC20Mock(weth).balanceOf(USER);
    uint256 collateralBeforeRedeem = engine.getAccountCollateralTokenAmount(USER, weth);

    dsc.approve(address(engine), BURN_AMOUNT); // don't forget to approve engine to transfer your dsc
    engine.redeemCollateralForDsc(weth, REDEEM_COLLATERAL, BURN_AMOUNT);

    uint256 dscBalanceAfterBurn = dsc.balanceOf(USER);
    uint256 dscTotalSupplyAfterBurn = dsc.totalSupply();
    (uint256 dscMintedAfterBurn,) = engine.getAccountInfo(USER);
    uint256 wethBalanceAfterRedeem = ERC20Mock(weth).balanceOf(USER);
    uint256 collateralAfterRedeem = engine.getAccountCollateralTokenAmount(USER, weth);

    assertEq(dscBalanceAfterBurn, dscBalanceBeforeBurn - BURN_AMOUNT);
    assertEq(dscTotalSupplyAfterBurn, dscTotalSupplyBeforeBurn - BURN_AMOUNT);
    assertEq(dscMintedAfterBurn, dscMintedBeforBurn - BURN_AMOUNT);
    assertEq(wethBalanceAfterRedeem, wethBalanceBeforeRedeem + REDEEM_COLLATERAL);
    assertEq(collateralAfterRedeem, collateralBeforeRedeem - REDEEM_COLLATERAL);
  }

  /*//////////////////////////////////////////////////////////////
                          LIQUIDATION TESTS
  //////////////////////////////////////////////////////////////*/

  function testLiquidationRevertsIfHealthFactorIsNotBroken() public {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
    vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
    engine.liquidate(weth, USER, AMOUNT_MINT);
    vm.stopPrank();
  }

  modifier liquidated() {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
    vm.stopPrank();

    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(LIQUIDATION_PRICE);

    ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_TO_COVER);

    vm.startPrank(LIQUIDATOR);
    ERC20Mock(weth).approve(address(engine), AMOUNT_TO_COVER);
    engine.depositCollateralAndMintDsc(weth, AMOUNT_TO_COVER, AMOUNT_MINT);
    dsc.approve(address(engine), AMOUNT_MINT);
    engine.liquidate(weth, USER, AMOUNT_MINT); // We are covering their whole debt
    vm.stopPrank();
    _;
  }

  function testLiquidationPayouts() public liquidated {
    uint256 liquidatorWeth = ERC20Mock(weth).balanceOf(LIQUIDATOR);
    (,, uint256 totalCollateralToRedeem) = engine.estimateLiquidationProfit(weth, AMOUNT_MINT);
    assertEq(liquidatorWeth, totalCollateralToRedeem);
  }
}
