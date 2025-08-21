// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/PropertyOracle.sol";

contract PropertyOracleTest is Test {
    PropertyOracle public oracle;
    address public owner;
    address public user1;
    address public mockUSDC;
    
    // Test property data
    PropertyOracle.PropertyData public testProperty;
    
    event PropertyAdded(uint256 indexed propertyId, address indexed landlord, uint256 minRaising, uint256 maxRaising);
    event PropertyUpdated(uint256 indexed propertyId, uint64 version);
    event PropertyRemoved(uint256 indexed propertyId);
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        mockUSDC = makeAddr("mockUSDC");
        
        oracle = new PropertyOracle();
        
        // Setup test property data
        testProperty = PropertyOracle.PropertyData({
            propertyId: 1001,
            payoutToken: mockUSDC,
            valuation: 1_000_000 * 1e6, // 1M USDC
            minRaising: 100_000 * 1e6,  // 100K USDC
            maxRaising: 800_000 * 1e6,  // 800K USDC
            accrualStart: uint64(block.timestamp + 1 days),
            accrualEnd: uint64(block.timestamp + 365 days),
            landlord: makeAddr("landlord"),
            docHash: keccak256("property_documents"),
            offchainURL: "https://ipfs.io/ipfs/QmTest"
        });
    }
    
    // ========== 正常场景测试 ==========
    
    function test_AddProperty_Success() public {
        vm.expectEmit(true, false, false, true);
        emit PropertyUpdated(1001, 1);
        
        vm.expectEmit(true, true, false, true);
        emit PropertyAdded(1001, testProperty.landlord, testProperty.minRaising, testProperty.maxRaising);
        
        oracle.addOrUpdateProperty(1001, testProperty);
        
        // Verify property was added
        (PropertyOracle.PropertyData memory data, uint64 version) = oracle.getProperty(1001);
        assertEq(data.propertyId, 1001);
        assertEq(data.payoutToken, mockUSDC);
        assertEq(data.valuation, 1_000_000 * 1e6);
        assertEq(data.minRaising, 100_000 * 1e6);
        assertEq(data.maxRaising, 800_000 * 1e6);
        assertEq(data.landlord, testProperty.landlord);
        assertEq(version, 1);
        
        // Check version tracking
        assertEq(oracle.versionOf(1001), 1);
        assertTrue(oracle.propertyExists(1001));
    }
    
    function test_UpdateProperty_Success() public {
        // Add initial property
        oracle.addOrUpdateProperty(1001, testProperty);
        
        // Update property
        testProperty.valuation = 1_200_000 * 1e6; // Increase valuation
        testProperty.maxRaising = 900_000 * 1e6;  // Increase max raising
        
        vm.expectEmit(true, false, false, true);
        emit PropertyUpdated(1001, 2);
        
        oracle.addOrUpdateProperty(1001, testProperty);
        
        // Verify update
        (PropertyOracle.PropertyData memory data, uint64 version) = oracle.getProperty(1001);
        assertEq(data.valuation, 1_200_000 * 1e6);
        assertEq(data.maxRaising, 900_000 * 1e6);
        assertEq(version, 2);
    }
    
    function test_RemoveProperty_Success() public {
        // Add property first
        oracle.addOrUpdateProperty(1001, testProperty);
        assertTrue(oracle.propertyExists(1001));
        
        vm.expectEmit(true, false, false, true);
        emit PropertyRemoved(1001);
        
        oracle.removeProperty(1001);
        
        // Verify removal
        assertFalse(oracle.propertyExists(1001));
    }
    
    function test_GetPropertyPacked_Success() public {
        oracle.addOrUpdateProperty(1001, testProperty);
        
        (bytes memory packed, uint64 version) = oracle.getPropertyPacked(1001);
        assertGt(packed.length, 0);
        assertEq(version, 1);
        
        // Decode and verify
        PropertyOracle.PropertyData memory decoded = abi.decode(packed, (PropertyOracle.PropertyData));
        assertEq(decoded.propertyId, 1001);
        assertEq(decoded.payoutToken, mockUSDC);
    }
    
    // ========== 异常场景测试 ==========
    
    function test_AddProperty_InvalidTimeRange() public {
        testProperty.accrualStart = uint64(block.timestamp + 365 days);
        testProperty.accrualEnd = uint64(block.timestamp + 1 days); // End before start
        
        vm.expectRevert("PropertyOracle: Invalid time range");
        oracle.addOrUpdateProperty(1001, testProperty);
    }
    
    function test_AddProperty_InvalidRaisingRange() public {
        testProperty.minRaising = 800_000 * 1e6;
        testProperty.maxRaising = 100_000 * 1e6; // Max less than min
        
        vm.expectRevert("PropertyOracle: Invalid raising range");
        oracle.addOrUpdateProperty(1001, testProperty);
    }
    
    function test_AddProperty_InvalidPayoutToken() public {
        testProperty.payoutToken = address(0);
        
        vm.expectRevert("PropertyOracle: Invalid payout token");
        oracle.addOrUpdateProperty(1001, testProperty);
    }
    
    function test_AddProperty_InvalidLandlord() public {
        testProperty.landlord = address(0);
        
        vm.expectRevert("PropertyOracle: Invalid landlord");
        oracle.addOrUpdateProperty(1001, testProperty);
    }
    
    function test_AddProperty_IDMismatch() public {
        vm.expectRevert("PropertyOracle: ID mismatch");
        oracle.addOrUpdateProperty(1002, testProperty); // ID mismatch
    }
    
    function test_GetProperty_NotFound() public {
        vm.expectRevert("PropertyOracle: Property not found");
        oracle.getProperty(9999);
    }
    
    function test_GetPropertyPacked_NotFound() public {
        vm.expectRevert("PropertyOracle: Property not found");
        oracle.getPropertyPacked(9999);
    }
    
    function test_RemoveProperty_NotFound() public {
        vm.expectRevert("PropertyOracle: Property not found");
        oracle.removeProperty(9999);
    }
    
    // ========== 权限测试 ==========
    
    function test_AddProperty_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        oracle.addOrUpdateProperty(1001, testProperty);
    }
    
    function test_RemoveProperty_OnlyOwner() public {
        oracle.addOrUpdateProperty(1001, testProperty);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        oracle.removeProperty(1001);
    }
    
    function test_Pause_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        oracle.pause();
    }
    
    function test_Unpause_OnlyOwner() public {
        oracle.pause();
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        oracle.unpause();
    }
    
    // ========== 暂停功能测试 ==========
    
    function test_Pause_Success() public {
        oracle.pause();
        assertTrue(oracle.paused());
    }
    
    function test_Unpause_Success() public {
        oracle.pause();
        oracle.unpause();
        assertFalse(oracle.paused());
    }
    
    // ========== 边界条件测试 ==========
    
    function test_PropertyVersion_MultipleUpdates() public {
        oracle.addOrUpdateProperty(1001, testProperty);
        assertEq(oracle.versionOf(1001), 1);
        
        // Multiple updates
        for (uint256 i = 2; i <= 10; i++) {
            testProperty.valuation = testProperty.valuation + 1000 * 1e6;
            oracle.addOrUpdateProperty(1001, testProperty);
            assertEq(oracle.versionOf(1001), i);
        }
    }
    
    function test_PropertyExists_EdgeCases() public {
        assertFalse(oracle.propertyExists(0));
        assertFalse(oracle.propertyExists(type(uint256).max));
        
        oracle.addOrUpdateProperty(1001, testProperty);
        assertTrue(oracle.propertyExists(1001));
        
        oracle.removeProperty(1001);
        assertFalse(oracle.propertyExists(1001));
    }
    
    function test_VersionOf_NonExistentProperty() public {
        assertEq(oracle.versionOf(9999), 0);
    }
    
    // ========== 多房产管理测试 ==========
    
    function test_MultipleProperties_Management() public {
        // Add multiple properties
        for (uint256 i = 1001; i <= 1010; i++) {
            PropertyOracle.PropertyData memory prop = testProperty;
            prop.propertyId = i;
            prop.landlord = makeAddr(string(abi.encodePacked("landlord", vm.toString(i))));
            
            oracle.addOrUpdateProperty(i, prop);
            assertTrue(oracle.propertyExists(i));
            assertEq(oracle.versionOf(i), 1);
        }
        
        // Verify all properties exist
        for (uint256 i = 1001; i <= 1010; i++) {
            (PropertyOracle.PropertyData memory data,) = oracle.getProperty(i);
            assertEq(data.propertyId, i);
        }
        
        // Remove some properties
        oracle.removeProperty(1005);
        oracle.removeProperty(1008);
        
        assertFalse(oracle.propertyExists(1005));
        assertFalse(oracle.propertyExists(1008));
        assertTrue(oracle.propertyExists(1001));
        assertTrue(oracle.propertyExists(1010));
    }
}