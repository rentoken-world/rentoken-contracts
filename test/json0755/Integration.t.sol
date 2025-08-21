// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/SeriesFactory.sol";
import "../../src/PropertyOracle.sol";
import "../../src/RentToken.sol";
import "../../src/KYCOracle.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockSanctionOracle.sol";

contract IntegrationTest is Test {
    SeriesFactory public factory;
    PropertyOracle public propertyOracle;
    RentToken public rentTokenImpl;
    KYCOracle public kycOracle;
    MockSanctionOracle public sanctionOracle;
    MockUSDC public usdc;
    
    address public admin;
    address public operator;
    address public landlord1;
    address public landlord2;
    address public investor1;
    address public investor2;
    address public investor3;
    
    uint256 public constant PROPERTY_ID_1 = 1001;
    uint256 public constant PROPERTY_ID_2 = 1002;
    
    PropertyOracle.PropertyData public property1;
    PropertyOracle.PropertyData public property2;
    
    function setUp() public {
        admin = address(this);
        operator = makeAddr("operator");
        landlord1 = makeAddr("landlord1");
        landlord2 = makeAddr("landlord2");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        investor3 = makeAddr("investor3");
        
        // Deploy all contracts
        usdc = new MockUSDC();
        propertyOracle = new PropertyOracle();
        kycOracle = new KYCOracle();
        sanctionOracle = new MockSanctionOracle();
        rentTokenImpl = new RentToken();
        factory = new SeriesFactory(address(propertyOracle));
        
        // Setup factory
        factory.updateRentTokenImplementation(address(rentTokenImpl));
        factory.grantOperatorRole(operator);
        
        // Setup properties
        property1 = PropertyOracle.PropertyData({
            propertyId: PROPERTY_ID_1,
            payoutToken: address(usdc),
            valuation: 1_000_000 * 1e6,
            minRaising: 100_000 * 1e6,
            maxRaising: 800_000 * 1e6,
            accrualStart: uint64(block.timestamp + 7 days),
            accrualEnd: uint64(block.timestamp + 365 days),
            landlord: landlord1,
            docHash: keccak256("property1_docs"),
            offchainURL: "https://ipfs.io/ipfs/QmProperty1"
        });
        
        property2 = PropertyOracle.PropertyData({
            propertyId: PROPERTY_ID_2,
            payoutToken: address(usdc),
            valuation: 2_000_000 * 1e6,
            minRaising: 200_000 * 1e6,
            maxRaising: 1_600_000 * 1e6,
            accrualStart: uint64(block.timestamp + 14 days),
            accrualEnd: uint64(block.timestamp + 730 days),
            landlord: landlord2,
            docHash: keccak256("property2_docs"),
            offchainURL: "https://ipfs.io/ipfs/QmProperty2"
        });
        
        propertyOracle.addOrUpdateProperty(PROPERTY_ID_1, property1);
        propertyOracle.addOrUpdateProperty(PROPERTY_ID_2, property2);
        
        // Setup KYC whitelist
        kycOracle.addToWhitelist(investor1);
        kycOracle.addToWhitelist(investor2);
        kycOracle.addToWhitelist(investor3);
        
        // Mint USDC to participants
        usdc.mint(investor1, 1_000_000 * 1e6);
        usdc.mint(investor2, 1_000_000 * 1e6);
        usdc.mint(investor3, 1_000_000 * 1e6);
        usdc.mint(operator, 5_000_000 * 1e6);
    }
    
    // ========== 完整业务流程测试 ==========
    
    function test_CompletePropertyLifecycle() public {
        // 1. Create series
        address series1Address = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam 001", "RTAMS1");
        RentToken series1 = RentToken(series1Address);
        
        // Setup oracles
        factory.setOraclesForSeries(PROPERTY_ID_1, address(kycOracle), address(sanctionOracle));
        
        // 2. Fundraising phase - multiple investors contribute
        uint256 investment1 = 60_000 * 1e6;
        uint256 investment2 = 50_000 * 1e6;
        
        vm.startPrank(investor1);
        usdc.approve(series1Address, investment1);
        series1.contribute(investment1);
        vm.stopPrank();
        
        vm.startPrank(investor2);
        usdc.approve(series1Address, investment2);
        series1.contribute(investment2);
        vm.stopPrank();
        
        // Verify fundraising state
        assertEq(series1.totalFundRaised(), investment1 + investment2);
        assertEq(series1.balanceOf(investor1), investment1);
        assertEq(series1.balanceOf(investor2), investment2);
        assertEq(uint256(series1.getPhase()), uint256(RentToken.Phase.Fundraising));
        
        // 3. Move to running phase
        vm.warp(property1.accrualStart + 1);
        assertEq(uint256(series1.getPhase()), uint256(RentToken.Phase.AccrualStarted));
        
        // 4. Receive and distribute profits multiple times
        uint256[] memory profits = new uint256[](3);
        profits[0] = 2000 * 1e6; // Month 1
        profits[1] = 2500 * 1e6; // Month 2
        profits[2] = 1800 * 1e6; // Month 3
        
        uint256 totalProfits = 0;
        for (uint256 i = 0; i < profits.length; i++) {
            vm.startPrank(operator);
            usdc.approve(address(factory), profits[i]);
            factory.receiveProfit(PROPERTY_ID_1, profits[i]);
            vm.stopPrank();
            
            totalProfits += profits[i];
            
            // Verify profit distribution
            assertEq(series1.totalProfitReceived(), totalProfits);
        }
        
        // 5. Investors claim their profits
        uint256 totalInvestment = investment1 + investment2;
        uint256 expectedProfit1 = totalProfits * investment1 / totalInvestment;
        uint256 expectedProfit2 = totalProfits * investment2 / totalInvestment;
        
        assertEq(series1.getClaimableAmount(investor1), expectedProfit1);
        assertEq(series1.getClaimableAmount(investor2), expectedProfit2);
        
        uint256 balance1Before = usdc.balanceOf(investor1);
        uint256 balance2Before = usdc.balanceOf(investor2);
        
        vm.prank(investor1);
        series1.claim();
        
        vm.prank(investor2);
        series1.claim();
        
        assertEq(usdc.balanceOf(investor1) - balance1Before, expectedProfit1);
        assertEq(usdc.balanceOf(investor2) - balance2Before, expectedProfit2);
        
        // 6. Move to expired phase
        vm.warp(property1.accrualEnd + 1);
        assertEq(uint256(series1.getPhase()), uint256(RentToken.Phase.AccrualFinished));
    }
    
    function test_MultiplePropertiesManagement() public {
        // Create series for both properties
        address series1Address = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam", "RTAMS");
        address series2Address = factory.createSeries(PROPERTY_ID_2, "RenToken Berlin", "RTBER");
        
        RentToken series1 = RentToken(series1Address);
        RentToken series2 = RentToken(series2Address);
        
        // Setup oracles for both
        factory.setOraclesForSeries(PROPERTY_ID_1, address(kycOracle), address(sanctionOracle));
        factory.setOraclesForSeries(PROPERTY_ID_2, address(kycOracle), address(sanctionOracle));
        
        // Investors contribute to both properties
        vm.startPrank(investor1);
        usdc.approve(series1Address, property1.minRaising);
        series1.contribute(property1.minRaising);
        
        usdc.approve(series2Address, property2.minRaising);
        series2.contribute(property2.minRaising);
        vm.stopPrank();
        
        // Verify both series are funded
        assertTrue(series1.totalFundRaised() >= property1.minRaising);
        assertTrue(series2.totalFundRaised() >= property2.minRaising);
        
        // Move both to running phase
        vm.warp(property1.accrualStart + 1);
        assertEq(uint256(series1.getPhase()), uint256(RentToken.Phase.AccrualStarted));
        
        vm.warp(property2.accrualStart + 1);
        assertEq(uint256(series2.getPhase()), uint256(RentToken.Phase.AccrualStarted));
        
        // Distribute profits to both
        vm.startPrank(operator);
        usdc.approve(address(factory), 10_000 * 1e6);
        factory.receiveProfit(PROPERTY_ID_1, 3000 * 1e6);
        factory.receiveProfit(PROPERTY_ID_2, 5000 * 1e6);
        vm.stopPrank();
        
        // Verify independent profit tracking
        assertEq(series1.totalProfitReceived(), 3000 * 1e6);
        assertEq(series2.totalProfitReceived(), 5000 * 1e6);
        
        // Investor can claim from both
        assertGt(series1.getClaimableAmount(investor1), 0);
        assertGt(series2.getClaimableAmount(investor1), 0);
    }
    
    function test_FundraisingFailureScenario() public {
        // Create series
        address seriesAddress = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam", "RTAMS");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID_1, address(kycOracle), address(sanctionOracle));
        
        // Contribute less than minimum required
        uint256 insufficientAmount = property1.minRaising - 1000 * 1e6;
        
        vm.startPrank(investor1);
        usdc.approve(seriesAddress, insufficientAmount);
        series.contribute(insufficientAmount);
        vm.stopPrank();
        
        // Move past accrual start
        vm.warp(property1.accrualStart + 1);
        
        // Verify fundraising failed
        assertEq(uint256(series.getPhase()), uint256(RentToken.Phase.RisingFailed));
        
        // Investor can get refund
        uint256 balanceBefore = usdc.balanceOf(investor1);
        
        vm.prank(investor1);
        series.refund();
        
        uint256 balanceAfter = usdc.balanceOf(investor1);
        assertEq(balanceAfter - balanceBefore, insufficientAmount);
        assertEq(series.balanceOf(investor1), 0);
    }
    
    function test_TokenTransferWithProfitTracking() public {
        // Setup series with contributions
        address seriesAddress = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam", "RTAMS");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID_1, address(kycOracle), address(sanctionOracle));
        
        // investor2 is already whitelisted in setUp
        
        uint256 investment = property1.minRaising;
        
        vm.startPrank(investor1);
        usdc.approve(seriesAddress, investment);
        series.contribute(investment);
        vm.stopPrank();
        
        // Move to running phase and distribute profit
        vm.warp(property1.accrualStart + 1);
        
        vm.startPrank(operator);
        usdc.approve(address(factory), 5000 * 1e6);
        factory.receiveProfit(PROPERTY_ID_1, 5000 * 1e6);
        vm.stopPrank();
        
        // Investor1 transfers half tokens to investor2
        uint256 transferAmount = investment / 2;
        
        vm.prank(investor1);
        series.transfer(investor2, transferAmount);
        
        // Verify balances
        assertEq(series.balanceOf(investor1), investment - transferAmount);
        assertEq(series.balanceOf(investor2), transferAmount);
        
        // After transfer, investor1 should have all the previous profits
        // investor2 should have 0 claimable (no profits earned yet)
        uint256 claimable1 = series.getClaimableAmount(investor1);
        uint256 claimable2 = series.getClaimableAmount(investor2);
        
        assertGt(claimable1, 0);
        assertEq(claimable2, 0); // investor2 hasn't earned any profits yet
        
        // Distribute new profit after transfer
        vm.startPrank(operator);
        usdc.approve(address(factory), 2500 * 1e6);
        factory.receiveProfit(PROPERTY_ID_1, 2500 * 1e6);
        vm.stopPrank();
        
        // Now both should have claimable amounts based on their current holdings
        claimable1 = series.getClaimableAmount(investor1);
        claimable2 = series.getClaimableAmount(investor2);
        
        assertGt(claimable1, 0);
        assertGt(claimable2, 0);
        // New profit should be split proportionally: 1250 each (50% each)
        assertEq(claimable2, 1250 * 1e6);
    }
    
    function test_KYCAndSanctionIntegration() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam", "RTAMS");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID_1, address(kycOracle), address(sanctionOracle));
        
        // Test KYC requirement
        address nonKYCUser = makeAddr("nonKYC");
        usdc.mint(nonKYCUser, 100_000 * 1e6);
        
        vm.startPrank(nonKYCUser);
        usdc.approve(seriesAddress, 50_000 * 1e6);
        vm.expectRevert("RentToken: User not whitelisted");
        series.contribute(50_000 * 1e6);
        vm.stopPrank();
        
        // Add to KYC and try again
        kycOracle.addToWhitelist(nonKYCUser);
        
        vm.startPrank(nonKYCUser);
        series.contribute(50_000 * 1e6);
        vm.stopPrank();
        
        assertEq(series.balanceOf(nonKYCUser), 50_000 * 1e6);
        
        // Test sanction blocking transfer
        sanctionOracle.setBlocked(investor1, true);
        
        vm.startPrank(nonKYCUser);
        vm.expectRevert("RentToken: Recipient is sanctioned");
        series.transfer(investor1, 10_000 * 1e6);
        vm.stopPrank();
    }
    
    function test_EmergencyScenarios() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam", "RTAMS");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID_1, address(kycOracle), address(sanctionOracle));
        
        // Contribute some funds
        vm.startPrank(investor1);
        usdc.approve(seriesAddress, property1.minRaising);
        series.contribute(property1.minRaising);
        vm.stopPrank();
        
        // Test factory pause
        factory.pause();
        
        vm.startPrank(operator);
        usdc.approve(address(factory), 1000 * 1e6);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        factory.receiveProfit(PROPERTY_ID_1, 1000 * 1e6);
        vm.stopPrank();
        
        factory.unpause();
        
        // Test series pause (need to transfer ownership first)
        vm.prank(address(factory));
        series.transferOwnership(admin);
        
        series.pause();
        
        vm.startPrank(investor2);
        usdc.approve(seriesAddress, 10_000 * 1e6);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        series.contribute(10_000 * 1e6);
        vm.stopPrank();
        
        series.unpause();
        
        // Test emergency token recovery
        uint256 emergencyAmount = 1000 * 1e6;
        usdc.transfer(address(factory), emergencyAmount);
        
        uint256 balanceBefore = usdc.balanceOf(admin);
        factory.emergencyRecoverToken(address(usdc), admin, emergencyAmount);
        uint256 balanceAfter = usdc.balanceOf(admin);
        
        assertEq(balanceAfter - balanceBefore, emergencyAmount);
    }
    
    function test_PropertyOracleIntegration() public {
        // Test property update affecting existing series
        address seriesAddress = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam", "RTAMS");
        RentToken series = RentToken(seriesAddress);
        
        // Verify initial property data
        assertEq(series.payoutToken(), property1.payoutToken);
        assertEq(series.minRaising(), property1.minRaising);
        assertEq(series.maxRaising(), property1.maxRaising);
        
        // Update property in oracle (this shouldn't affect existing series)
        PropertyOracle.PropertyData memory updatedProperty = property1;
        updatedProperty.valuation = 1_500_000 * 1e6;
        propertyOracle.addOrUpdateProperty(PROPERTY_ID_1, updatedProperty);
        
        // Existing series should maintain original parameters
        assertEq(series.minRaising(), property1.minRaising);
        assertEq(series.maxRaising(), property1.maxRaising);
        
        // But new series would use updated parameters
        uint256 newPropertyId = 1003;
        updatedProperty.propertyId = newPropertyId;
        propertyOracle.addOrUpdateProperty(newPropertyId, updatedProperty);
        
        address newSeriesAddress = factory.createSeries(newPropertyId, "RenToken Amsterdam V2", "RTAMS2");
        RentToken newSeries = RentToken(newSeriesAddress);
        
        // New series should have updated parameters
        assertEq(newSeries.minRaising(), updatedProperty.minRaising);
        assertEq(newSeries.maxRaising(), updatedProperty.maxRaising);
    }
    
    function test_LargeScaleOperations() public {
        // Test with many investors and multiple profit distributions
        address seriesAddress = factory.createSeries(PROPERTY_ID_1, "RenToken Amsterdam", "RTAMS");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID_1, address(kycOracle), address(sanctionOracle));
        
        // Create and fund multiple investors
        address[] memory investors = new address[](10);
        uint256[] memory investments = new uint256[](10);
        uint256 totalInvestment = 0;
        
        for (uint256 i = 0; i < 10; i++) {
            investors[i] = makeAddr(string(abi.encodePacked("largeScaleInvestor", vm.toString(i))));
            investments[i] = (i + 1) * 10_000 * 1e6; // 10k, 20k, 30k, etc.
            totalInvestment += investments[i];
            
            kycOracle.addToWhitelist(investors[i]);
            usdc.mint(investors[i], investments[i]);
            
            vm.startPrank(investors[i]);
            usdc.approve(seriesAddress, investments[i]);
            series.contribute(investments[i]);
            vm.stopPrank();
        }
        
        // Move to running phase
        vm.warp(property1.accrualStart + 1);
        
        // Multiple profit distributions
        uint256[] memory profits = new uint256[](5);
        profits[0] = 5000 * 1e6;
        profits[1] = 7500 * 1e6;
        profits[2] = 6000 * 1e6;
        profits[3] = 8000 * 1e6;
        profits[4] = 4500 * 1e6;
        
        uint256 totalProfits = 0;
        for (uint256 i = 0; i < profits.length; i++) {
            vm.startPrank(operator);
            usdc.approve(address(factory), profits[i]);
            factory.receiveProfit(PROPERTY_ID_1, profits[i]);
            vm.stopPrank();
            
            totalProfits += profits[i];
        }
        
        // Verify all investors can claim proportional profits
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < investors.length; i++) {
            uint256 expectedProfit = totalProfits * investments[i] / totalInvestment;
            uint256 claimableAmount = series.getClaimableAmount(investors[i]);
            
            // Allow for small rounding differences
            assertApproxEqAbs(claimableAmount, expectedProfit, 1);
            
            vm.prank(investors[i]);
            series.claim();
            
            totalClaimed += claimableAmount;
        }
        
        // Total claimed should equal total profits (within rounding)
        assertApproxEqAbs(totalClaimed, totalProfits, investors.length);
    }
}