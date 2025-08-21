// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/KYCOracle.sol";

contract KYCOracleTest is Test {
    KYCOracle public kycOracle;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    event AddressWhitelisted(address indexed addr);
    event AddressRemoved(address indexed addr);
    event BatchWhitelistUpdated(address[] addresses, bool[] statuses);
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        kycOracle = new KYCOracle();
    }
    
    // ========== 单个地址白名单测试 ==========
    
    function test_AddToWhitelist_Success() public {
        assertFalse(kycOracle.isWhitelisted(user1));
        
        vm.expectEmit(true, false, false, false);
        emit AddressWhitelisted(user1);
        
        kycOracle.addToWhitelist(user1);
        
        assertTrue(kycOracle.isWhitelisted(user1));
        assertTrue(kycOracle.kycWhitelist(user1));
    }
    
    function test_RemoveFromWhitelist_Success() public {
        // First add to whitelist
        kycOracle.addToWhitelist(user1);
        assertTrue(kycOracle.isWhitelisted(user1));
        
        vm.expectEmit(true, false, false, false);
        emit AddressRemoved(user1);
        
        kycOracle.removeFromWhitelist(user1);
        
        assertFalse(kycOracle.isWhitelisted(user1));
        assertFalse(kycOracle.kycWhitelist(user1));
    }
    
    function test_AddToWhitelist_InvalidAddress() public {
        vm.expectRevert("KYCOracle: Invalid address");
        kycOracle.addToWhitelist(address(0));
    }
    
    function test_AddToWhitelist_AlreadyWhitelisted() public {
        kycOracle.addToWhitelist(user1);
        
        vm.expectRevert("KYCOracle: Already whitelisted");
        kycOracle.addToWhitelist(user1);
    }
    
    function test_RemoveFromWhitelist_NotWhitelisted() public {
        vm.expectRevert("KYCOracle: Not whitelisted");
        kycOracle.removeFromWhitelist(user1);
    }
    
    // ========== 批量操作测试 ==========
    
    function test_BatchUpdateWhitelist_Success() public {
        address[] memory addresses = new address[](3);
        bool[] memory statuses = new bool[](3);
        
        addresses[0] = user1;
        addresses[1] = user2;
        addresses[2] = user3;
        statuses[0] = true;
        statuses[1] = true;
        statuses[2] = false;
        
        vm.expectEmit(true, false, false, false);
        emit AddressWhitelisted(user1);
        vm.expectEmit(true, false, false, false);
        emit AddressWhitelisted(user2);
        vm.expectEmit(true, false, false, false);
        emit AddressRemoved(user3);
        vm.expectEmit(false, false, false, true);
        emit BatchWhitelistUpdated(addresses, statuses);
        
        kycOracle.batchUpdateWhitelist(addresses, statuses);
        
        assertTrue(kycOracle.isWhitelisted(user1));
        assertTrue(kycOracle.isWhitelisted(user2));
        assertFalse(kycOracle.isWhitelisted(user3));
    }
    
    function test_BatchUpdateWhitelist_ArrayLengthMismatch() public {
        address[] memory addresses = new address[](2);
        bool[] memory statuses = new bool[](3);
        
        addresses[0] = user1;
        addresses[1] = user2;
        statuses[0] = true;
        statuses[1] = true;
        statuses[2] = false;
        
        vm.expectRevert("KYCOracle: Array length mismatch");
        kycOracle.batchUpdateWhitelist(addresses, statuses);
    }
    
    function test_BatchUpdateWhitelist_InvalidAddress() public {
        address[] memory addresses = new address[](2);
        bool[] memory statuses = new bool[](2);
        
        addresses[0] = user1;
        addresses[1] = address(0); // Invalid address
        statuses[0] = true;
        statuses[1] = true;
        
        vm.expectRevert("KYCOracle: Invalid address");
        kycOracle.batchUpdateWhitelist(addresses, statuses);
    }
    
    function test_BatchCheckWhitelist_Success() public {
        // Add some addresses to whitelist
        kycOracle.addToWhitelist(user1);
        kycOracle.addToWhitelist(user3);
        
        address[] memory addresses = new address[](3);
        addresses[0] = user1;
        addresses[1] = user2;
        addresses[2] = user3;
        
        bool[] memory results = kycOracle.batchCheckWhitelist(addresses);
        
        assertEq(results.length, 3);
        assertTrue(results[0]);  // user1 is whitelisted
        assertFalse(results[1]); // user2 is not whitelisted
        assertTrue(results[2]);  // user3 is whitelisted
    }
    
    function test_BatchCheckWhitelist_EmptyArray() public {
        address[] memory addresses = new address[](0);
        bool[] memory results = kycOracle.batchCheckWhitelist(addresses);
        assertEq(results.length, 0);
    }
    
    // ========== 权限测试 ==========
    
    function test_AddToWhitelist_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        kycOracle.addToWhitelist(user2);
    }
    
    function test_RemoveFromWhitelist_OnlyOwner() public {
        kycOracle.addToWhitelist(user1);
        
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user2));
        kycOracle.removeFromWhitelist(user1);
    }
    
    function test_BatchUpdateWhitelist_OnlyOwner() public {
        address[] memory addresses = new address[](1);
        bool[] memory statuses = new bool[](1);
        addresses[0] = user1;
        statuses[0] = true;
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        kycOracle.batchUpdateWhitelist(addresses, statuses);
    }
    
    // ========== 查询功能测试 ==========
    
    function test_IsWhitelisted_DefaultFalse() public {
        assertFalse(kycOracle.isWhitelisted(user1));
        assertFalse(kycOracle.isWhitelisted(user2));
        assertFalse(kycOracle.isWhitelisted(address(0)));
    }
    
    function test_IsWhitelisted_AfterOperations() public {
        // Test after adding
        kycOracle.addToWhitelist(user1);
        assertTrue(kycOracle.isWhitelisted(user1));
        
        // Test after removing
        kycOracle.removeFromWhitelist(user1);
        assertFalse(kycOracle.isWhitelisted(user1));
        
        // Test after batch update
        address[] memory addresses = new address[](2);
        bool[] memory statuses = new bool[](2);
        addresses[0] = user1;
        addresses[1] = user2;
        statuses[0] = true;
        statuses[1] = false;
        
        kycOracle.batchUpdateWhitelist(addresses, statuses);
        assertTrue(kycOracle.isWhitelisted(user1));
        assertFalse(kycOracle.isWhitelisted(user2));
    }
    
    // ========== 边界条件测试 ==========
    
    function test_LargeScaleBatchUpdate() public {
        uint256 batchSize = 100;
        address[] memory addresses = new address[](batchSize);
        bool[] memory statuses = new bool[](batchSize);
        
        // Generate test addresses
        for (uint256 i = 0; i < batchSize; i++) {
            addresses[i] = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
            statuses[i] = i % 2 == 0; // Alternate true/false
        }
        
        kycOracle.batchUpdateWhitelist(addresses, statuses);
        
        // Verify results
        for (uint256 i = 0; i < batchSize; i++) {
            assertEq(kycOracle.isWhitelisted(addresses[i]), statuses[i]);
        }
    }
    
    function test_RepeatedOperations() public {
        // Add and remove the same address multiple times
        for (uint256 i = 0; i < 5; i++) {
            kycOracle.addToWhitelist(user1);
            assertTrue(kycOracle.isWhitelisted(user1));
            
            kycOracle.removeFromWhitelist(user1);
            assertFalse(kycOracle.isWhitelisted(user1));
        }
    }
    
    function test_BatchUpdateWithMixedOperations() public {
        // First add some addresses individually
        kycOracle.addToWhitelist(user1);
        kycOracle.addToWhitelist(user2);
        
        // Then use batch update to modify them
        address[] memory addresses = new address[](3);
        bool[] memory statuses = new bool[](3);
        addresses[0] = user1; // Remove existing
        addresses[1] = user2; // Keep existing
        addresses[2] = user3; // Add new
        statuses[0] = false;
        statuses[1] = true;
        statuses[2] = true;
        
        kycOracle.batchUpdateWhitelist(addresses, statuses);
        
        assertFalse(kycOracle.isWhitelisted(user1));
        assertTrue(kycOracle.isWhitelisted(user2));
        assertTrue(kycOracle.isWhitelisted(user3));
    }
    
    // ========== Gas 优化测试 ==========
    
    function test_GasUsage_SingleOperations() public {
        uint256 gasBefore = gasleft();
        kycOracle.addToWhitelist(user1);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Gas usage should be reasonable for single operation
        assertLt(gasUsed, 100000);
        
        gasBefore = gasleft();
        kycOracle.removeFromWhitelist(user1);
        gasUsed = gasBefore - gasleft();
        
        assertLt(gasUsed, 100000);
    }
    
    function test_GasUsage_BatchOperations() public {
        address[] memory addresses = new address[](10);
        bool[] memory statuses = new bool[](10);
        
        for (uint256 i = 0; i < 10; i++) {
            addresses[i] = makeAddr(string(abi.encodePacked("batchUser", vm.toString(i))));
            statuses[i] = true;
        }
        
        uint256 gasBefore = gasleft();
        kycOracle.batchUpdateWhitelist(addresses, statuses);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Batch operations should be more gas efficient than individual operations
        assertLt(gasUsed, 500000);
    }
}