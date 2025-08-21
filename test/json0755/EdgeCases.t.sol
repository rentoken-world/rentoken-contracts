// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/SeriesFactory.sol";
import "../../src/PropertyOracle.sol";
import "../../src/RentToken.sol";
import "../../src/KYCOracle.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockSanctionOracle.sol";

contract EdgeCasesTest is Test {
    SeriesFactory public factory;
    PropertyOracle public propertyOracle;
    RentToken public rentTokenImpl;
    KYCOracle public kycOracle;
    MockSanctionOracle public sanctionOracle;
    MockUSDC public usdc;
    
    address public admin;
    address public operator;
    address public landlord;
    address public user1;
    address public user2;
    
    uint256 public constant PROPERTY_ID = 1001;
    PropertyOracle.PropertyData public testProperty;
    
    function setUp() public {
        admin = address(this);
        operator = makeAddr("operator");
        landlord = makeAddr("landlord");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy contracts
        usdc = new MockUSDC();
        propertyOracle = new PropertyOracle();
        kycOracle = new KYCOracle();
        sanctionOracle = new MockSanctionOracle();
        rentTokenImpl = new RentToken();
        factory = new SeriesFactory(address(propertyOracle));
        
        // Setup property
        testProperty = PropertyOracle.PropertyData({
            propertyId: PROPERTY_ID,
            payoutToken: address(usdc),
            valuation: 1_000_000 * 1e6,
            minRaising: 100_000 * 1e6,
            maxRaising: 800_000 * 1e6,
            accrualStart: uint64(block.timestamp + 86400),
            accrualEnd: uint64(block.timestamp + 86400 * 365),
            feeBps: 1000,
            landlord: landlord,
            docHash: keccak256("test"),
            city: "Test City",
            offchainURL: "https://test.com"
        });
        
        propertyOracle.addOrUpdateProperty(PROPERTY_ID, testProperty);
        factory.updateRentTokenImplementation(address(rentTokenImpl));
        factory.grantOperatorRole(operator);
        
        // Setup KYC and mint tokens
        kycOracle.addToWhitelist(user1);
        kycOracle.addToWhitelist(user2);
        usdc.mint(user1, 1_000_000 * 1e6);
        usdc.mint(user2, 1_000_000 * 1e6);
        usdc.mint(operator, 1_000_000 * 1e6);
    }
    
    // Test minimum contribution
    function test_MinimumContribution() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));
        
        vm.startPrank(user1);
        usdc.approve(seriesAddress, 1);
        series.contribute(1);
        vm.stopPrank();
        
        assertEq(series.balanceOf(user1), 1);
    }
    
    // Test zero amount operations
    function test_ZeroAmountOperations() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));
        
        vm.startPrank(user1);
        vm.expectRevert("RentToken: Amount must be positive");
        series.contribute(0);
        vm.stopPrank();
        
        vm.startPrank(operator);
        vm.expectRevert("SeriesFactory: Amount must be positive");
        factory.receiveProfit(PROPERTY_ID, 0);
        vm.stopPrank();
    }
    
    // Test time boundary conditions
    function test_TimeBoundaryConditions() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));
        
        // Contribute to meet minimum
        vm.startPrank(user1);
        usdc.approve(seriesAddress, testProperty.minRaising);
        series.contribute(testProperty.minRaising);
        vm.stopPrank();
        
        // Test phase transitions
        vm.warp(testProperty.accrualStart - 1);
        assertEq(uint256(series.getPhase()), uint256(RentToken.Phase.Fundraising));
        
        vm.warp(testProperty.accrualStart);
        assertEq(uint256(series.getPhase()), uint256(RentToken.Phase.AccrualStarted));
        
        vm.warp(testProperty.accrualEnd + 1);
        assertEq(uint256(series.getPhase()), uint256(RentToken.Phase.AccrualFinished));
    }
    
    // Test permission boundaries
    function test_PermissionBoundaries() public {
        address unauthorizedUser = makeAddr("unauthorized");
        
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("SeriesFactory: Only admin can call");
        factory.createSeries(PROPERTY_ID, "Test", "T");
        vm.stopPrank();
        
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        
        vm.startPrank(unauthorizedUser);
        vm.expectRevert("SeriesFactory: Only operator can call");
        factory.receiveProfit(PROPERTY_ID, 1000 * 1e6);
        vm.stopPrank();
    }
    
    // Test oracle failures
    function test_OracleFailures() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        RentToken series = RentToken(seriesAddress);
        
        vm.startPrank(user1);
        usdc.approve(seriesAddress, 1000 * 1e6);
        vm.expectRevert();
        series.contribute(1000 * 1e6);
        vm.stopPrank();
        
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));
        
        vm.startPrank(user1);
        series.contribute(1000 * 1e6);
        vm.stopPrank();
        
        assertEq(series.balanceOf(user1), 1000 * 1e6);
    }
    
    // Test state inconsistency protection
    function test_StateInconsistencyProtection() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));
        
        vm.startPrank(user1);
        vm.expectRevert("RentToken: No profits to claim");
        series.claim(); // Should revert when no profits
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert("RentToken: Wrong phase");
        series.refund();
        vm.stopPrank();
        
        // Transfer ownership from factory to admin first
        vm.prank(address(factory));
        series.transferOwnership(admin);
        
        vm.prank(admin);
        series.pause();
        
        vm.startPrank(user1);
        usdc.approve(seriesAddress, 1000 * 1e6);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        series.contribute(1000 * 1e6);
        vm.stopPrank();
    }
    
    // Test concurrent operations
    function test_ConcurrentOperations() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        RentToken series = RentToken(seriesAddress);
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));
        
        uint256 amount1 = 60_000 * 1e6;
        uint256 amount2 = 40_000 * 1e6;
        
        vm.startPrank(user1);
        usdc.approve(seriesAddress, amount1);
        series.contribute(amount1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdc.approve(seriesAddress, amount2);
        series.contribute(amount2);
        vm.stopPrank();
        
        assertEq(series.balanceOf(user1), amount1);
        assertEq(series.balanceOf(user2), amount2);
        assertEq(series.totalFundRaised(), amount1 + amount2);
        
        vm.warp(testProperty.accrualStart + 1);
        
        vm.startPrank(operator);
        usdc.approve(address(factory), 10_000 * 1e6);
        factory.receiveProfit(PROPERTY_ID, 10_000 * 1e6);
        vm.stopPrank();
        
        uint256 claimable1 = series.getClaimableAmount(user1);
        uint256 claimable2 = series.getClaimableAmount(user2);
        
        vm.prank(user1);
        series.claim();
        
        vm.prank(user2);
        series.claim();
        
        assertEq(series.getClaimableAmount(user1), 0);
        assertEq(series.getClaimableAmount(user2), 0);
        assertEq(claimable1 + claimable2, 10_000 * 1e6);
    }
}