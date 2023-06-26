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
  address wbtc;

  address public immutable USER = makeAddr("user");
  address public immutable LIQUIDATOR = makeAddr("liquidator");
  address public immutable GETTERS_TESTER = makeAddr("getters-tester");

  uint256 public constant AMOUNT_COLLATERAL = 10 ether;
  uint256 public constant AMOUNT_TO_COVER = 20 ether;
  uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
  uint256 public constant AMOUNT_MINT = 100 ether;
  uint256 public constant BURN_AMOUNT = 50 ether;
  uint256 public constant REDEEM_COLLATERAL = 0.01 ether;

  function setUp() public {
    deployer = new DeployDSC();
    (dsc, engine, config) = deployer.run();
    (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
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

  function testGetUsdValue() public {
    uint256 ethAmount = 15e18;
    uint256 expectedUsdUncorrected = ethAmount * uint256(MockV3Aggregator(ethUsdPriceFeed).latestAnswer());
    uint256 expectedUsd = (expectedUsdUncorrected * engine.getAdditionalFeedPrecision()) / engine.getPresicion();
    uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    assertEq(actualUsd, expectedUsd);
  }

  function testGetTokenAmountFromUsd() public {
    uint256 usdAmountInWei = 100e18;
    // assume that price = 2000$ for 1 ETH (check helper config)
    uint256 expectedWeth = (engine.getPresicion() * usdAmountInWei)
      / (uint256(MockV3Aggregator(ethUsdPriceFeed).latestAnswer()) * engine.getAdditionalFeedPrecision());
    uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmountInWei);
    assertEq(actualWeth, expectedWeth);
  }

  /*//////////////////////////////////////////////////////////////
                        DEPOSIT COLLATERAL TESTS
  //////////////////////////////////////////////////////////////*/
  modifier deposited() {
    vm.startPrank(USER);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
    _;
  }

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

  function testCollateralValueInUsdIsCorrect() public deposited {
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
                            ESTIMATIONS
  //////////////////////////////////////////////////////////////*/
  function testEstimateCollateralOverhead() public deposited {
    uint256 estimatedOvercallteral = engine.estimateAccountOverheadCollateral(USER, weth);
    assertEq(estimatedOvercallteral, AMOUNT_COLLATERAL);
  }

  function testEstimateMaxMintable() public deposited {
    uint256 collateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
    assertEq(
      (collateralValueInUsd * engine.getLiquidationThreshold()) / engine.getLiquidationPrecision(),
      engine.estimateAccountMaxMintableDsc(USER)
    );
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

    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(engine.estimateLiquidationPriceForCollateralToken(weth, USER));

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

  /*//////////////////////////////////////////////////////////////
                        GETTERS FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function testGetCollateralTokens() public {
    address[] memory collateralTokens = engine.getCollateralTokens();
    assertEq(collateralTokens.length, 2);
    assertEq(collateralTokens[0], weth);
    assertEq(collateralTokens[1], wbtc);
  }

  function testGetCollateralPriceFeed() public {
    address receivedWethFeed = engine.getCollateralPriceFeed(weth);
    assertEq(receivedWethFeed, ethUsdPriceFeed);
  }
}
