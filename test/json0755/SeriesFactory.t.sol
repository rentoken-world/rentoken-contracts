// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/SeriesFactory.sol";
import "../../src/PropertyOracle.sol";
import "../../src/RentToken.sol";
import "../../src/KYCOracle.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockSanctionOracle.sol";

contract SeriesFactoryTest is Test {
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
    
    event SeriesCreated(uint256 indexed propertyId, address indexed seriesAddress, string name, string symbol);
    event ProfitForwarded(uint256 indexed propertyId, address indexed series, uint256 amount, address operator);
    
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
        
        // Setup property data
        testProperty = PropertyOracle.PropertyData({
            propertyId: PROPERTY_ID,
            payoutToken: address(usdc),
            valuation: 1_000_000 * 1e6,
            minRaising: 100_000 * 1e6,
            maxRaising: 800_000 * 1e6,
            accrualStart: uint64(block.timestamp + 1 days),
            accrualEnd: uint64(block.timestamp + 365 days),
            landlord: landlord,
            docHash: keccak256("property_docs"),
            offchainURL: "https://ipfs.io/ipfs/QmTest"
        });
        
        propertyOracle.addOrUpdateProperty(PROPERTY_ID, testProperty);
        factory.updateRentTokenImplementation(address(rentTokenImpl));
        factory.grantOperatorRole(operator);
        
        usdc.mint(operator, 1_000_000 * 1e6);
        usdc.mint(user1, 500_000 * 1e6);
        usdc.mint(user2, 500_000 * 1e6);
    }
    
    function test_CreateSeries_Success() public {
        string memory name = "RenToken Amsterdam 001";
        string memory symbol = "RTAMS1";
        
        address seriesAddress = factory.createSeries(PROPERTY_ID, name, symbol);
        
        assertNotEq(seriesAddress, address(0));
        assertEq(factory.getSeriesAddress(PROPERTY_ID), seriesAddress);
        assertTrue(factory.seriesExists(PROPERTY_ID));
        
        RentToken series = RentToken(seriesAddress);
        assertEq(series.name(), name);
        assertEq(series.symbol(), symbol);
        assertEq(series.propertyId(), PROPERTY_ID);
    }
    
    function test_CreateSeries_SeriesAlreadyExists() public {
        factory.createSeries(PROPERTY_ID, "Test1", "T1");
        
        vm.expectRevert("SeriesFactory: Series already exists");
        factory.createSeries(PROPERTY_ID, "Test2", "T2");
    }
    
    function test_CreateSeries_PropertyNotFound() public {
        vm.expectRevert("PropertyOracle: Property not found");
        factory.createSeries(9999, "Test", "T");
    }
    
    function test_ReceiveProfit_Success() public {
        address seriesAddress = factory.createSeries(PROPERTY_ID, "Test", "T");
        
        // Setup for accrual phase
        vm.warp(testProperty.accrualStart + 1);
        kycOracle.addToWhitelist(user1);
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));
        
        // User contributes to meet minimum raising
        vm.warp(testProperty.accrualStart - 1);
        vm.startPrank(user1);
        usdc.approve(seriesAddress, testProperty.minRaising);
        RentToken(seriesAddress).contribute(testProperty.minRaising);
        vm.stopPrank();
        
        vm.warp(testProperty.accrualStart + 1);
        
        uint256 profitAmount = 5000 * 1e6;
        vm.startPrank(operator);
        usdc.approve(address(factory), profitAmount);
        factory.receiveProfit(PROPERTY_ID, profitAmount);
        vm.stopPrank();
        
        assertEq(RentToken(seriesAddress).totalProfitReceived(), profitAmount);
    }
    
    function test_ReceiveProfit_SeriesNotFound() public {
        vm.prank(operator);
        vm.expectRevert("SeriesFactory: Series not found");
        factory.receiveProfit(9999, 1000 * 1e6);
    }
    
    function test_ReceiveProfit_OnlyOperator() public {
        factory.createSeries(PROPERTY_ID, "Test", "T");
        
        vm.prank(user1);
        vm.expectRevert("SeriesFactory: Only operator can call");
        factory.receiveProfit(PROPERTY_ID, 1000 * 1e6);
    }
    
    function test_UpdatePropertyOracle_Success() public {
        PropertyOracle newOracle = new PropertyOracle();
        factory.updatePropertyOracle(address(newOracle));
        assertEq(factory.propertyOracle(), address(newOracle));
    }
    
    function test_UpdatePropertyOracle_InvalidAddress() public {
        vm.expectRevert("SeriesFactory: Invalid oracle address");
        factory.updatePropertyOracle(address(0));
    }
    
    function test_GrantOperatorRole_Success() public {
        address newOperator = makeAddr("newOperator");
        factory.grantOperatorRole(newOperator);
        assertTrue(factory.hasRole(factory.OPERATOR_ROLE(), newOperator));
    }
    
    function test_Pause_Success() public {
        factory.pause();
        assertTrue(factory.paused());
    }
    
    function test_EmergencyRecoverToken_Success() public {
        uint256 amount = 1000 * 1e6;
        usdc.transfer(address(factory), amount);
        
        uint256 balanceBefore = usdc.balanceOf(admin);
        factory.emergencyRecoverToken(address(usdc), admin, amount);
        uint256 balanceAfter = usdc.balanceOf(admin);
        
        assertEq(balanceAfter - balanceBefore, amount);
    }
}