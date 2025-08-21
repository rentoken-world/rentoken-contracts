// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/SeriesFactory.sol";
import "../../src/PropertyOracle.sol";
import "../../src/RentToken.sol";
import "../../src/KYCOracle.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockSanctionOracle.sol";

contract RentTokenTest is Test {
    RentToken public rentToken;
    SeriesFactory public factory;
    PropertyOracle public propertyOracle;
    KYCOracle public kycOracle;
    MockSanctionOracle public sanctionOracle;
    MockUSDC public usdc;

    address public admin;
    address public landlord;
    address public user1;
    address public user2;
    address public user3;

    uint256 public constant PROPERTY_ID = 1001;
    PropertyOracle.PropertyData public testProperty;

    event ContributionReceived(address indexed contributor, uint256 amount, uint256 tokensIssued);
    event ProfitReceived(uint256 amount, uint256 newAccumulatedRewardPerToken);
    event ProfitClaimed(address indexed user, uint256 amount);
    event RefundProcessed(address indexed user, uint256 amount);
    event PhaseChanged(RentToken.Phase oldPhase, RentToken.Phase newPhase);

    function setUp() public {
        admin = address(this);
        landlord = makeAddr("landlord");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy contracts
        usdc = new MockUSDC();
        propertyOracle = new PropertyOracle();
        kycOracle = new KYCOracle();
        sanctionOracle = new MockSanctionOracle();

        // Setup property data
        testProperty = PropertyOracle.PropertyData({
            propertyId: PROPERTY_ID,
            payoutToken: address(usdc),
            valuation: 1_000_000 * 1e6,
            minRaising: 100_000 * 1e6,
            maxRaising: 800_000 * 1e6,
            accrualStart: uint64(block.timestamp + 7 days),
            accrualEnd: uint64(block.timestamp + 365 days),
            landlord: landlord,
            docHash: keccak256("property_docs"),
            offchainURL: "https://ipfs.io/ipfs/QmTest"
        });

        propertyOracle.addOrUpdateProperty(PROPERTY_ID, testProperty);

        // Deploy factory and create series
        RentToken implementation = new RentToken();
        factory = new SeriesFactory(address(propertyOracle));
        factory.updateRentTokenImplementation(address(implementation));

        address rentTokenAddress = factory.createSeries(PROPERTY_ID, "RenToken Amsterdam", "RTAMS");
        rentToken = RentToken(rentTokenAddress);

        // Setup oracles
        factory.setOraclesForSeries(PROPERTY_ID, address(kycOracle), address(sanctionOracle));

        // Setup KYC whitelist
        kycOracle.addToWhitelist(user1);
        kycOracle.addToWhitelist(user2);
        kycOracle.addToWhitelist(user3);

        // Mint USDC to users
        usdc.mint(user1, 1_000_000 * 1e6);
        usdc.mint(user2, 1_000_000 * 1e6);
        usdc.mint(user3, 1_000_000 * 1e6);
        usdc.mint(landlord, 1_000_000 * 1e6);
    }

    // ========== 阶段管理测试 ==========

    function test_GetPhase_Fundraising() public {
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.Fundraising));
    }

    function test_GetPhase_Running() public {
        // Contribute to meet minimum raising
        vm.startPrank(user1);
        usdc.approve(address(rentToken), testProperty.minRaising);
        rentToken.contribute(testProperty.minRaising);
        vm.stopPrank();

        // Move to accrual start
        vm.warp(testProperty.accrualStart + 1);
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.AccrualStarted));
    }

    function test_GetPhase_FundraisingFailed() public {
        // Move past accrual start without meeting minimum
        vm.warp(testProperty.accrualStart + 1);
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.RisingFailed));
    }

    function test_GetPhase_Expired() public {
        // Meet minimum raising first
        vm.startPrank(user1);
        usdc.approve(address(rentToken), testProperty.minRaising);
        rentToken.contribute(testProperty.minRaising);
        vm.stopPrank();

        // Move past accrual end
        vm.warp(testProperty.accrualEnd + 1);
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.AccrualFinished));
    }

    // ========== 募资阶段测试 ==========

    function test_Contribute_Success() public {
        uint256 amount = 50_000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rentToken), amount);

        vm.expectEmit(true, false, false, true);
        emit ContributionReceived(user1, amount, amount); // 1:1 ratio

        rentToken.contribute(amount);
        vm.stopPrank();

        assertEq(rentToken.balanceOf(user1), amount);
        assertEq(rentToken.totalFundRaised(), amount);
        assertEq(usdc.balanceOf(address(rentToken)), amount);
    }

    function test_Contribute_MultipleUsers() public {
        uint256 amount1 = 30_000 * 1e6;
        uint256 amount2 = 80_000 * 1e6;

        // User1 contributes
        vm.startPrank(user1);
        usdc.approve(address(rentToken), amount1);
        rentToken.contribute(amount1);
        vm.stopPrank();

        // User2 contributes
        vm.startPrank(user2);
        usdc.approve(address(rentToken), amount2);
        rentToken.contribute(amount2);
        vm.stopPrank();

        assertEq(rentToken.balanceOf(user1), amount1);
        assertEq(rentToken.balanceOf(user2), amount2);
        assertEq(rentToken.totalFundRaised(), amount1 + amount2);
    }

    function test_Contribute_ExceedsMaxRaising() public {
        vm.startPrank(user1);
        usdc.approve(address(rentToken), testProperty.maxRaising + 1);

        vm.expectRevert("RentToken: Exceeds max raising");
        rentToken.contribute(testProperty.maxRaising + 1);
        vm.stopPrank();
    }

    function test_Contribute_NotWhitelisted() public {
        address nonWhitelistedUser = makeAddr("nonWhitelisted");
        usdc.mint(nonWhitelistedUser, 100_000 * 1e6);

        vm.startPrank(nonWhitelistedUser);
        usdc.approve(address(rentToken), 50_000 * 1e6);

        vm.expectRevert("RentToken: Contributor not KYC verified");
        rentToken.contribute(50_000 * 1e6);
        vm.stopPrank();
    }

    function test_Contribute_SanctionedUser() public {
        sanctionOracle.setBlocked(user1, true);

        vm.startPrank(user1);
        usdc.approve(address(rentToken), 50_000 * 1e6);

        vm.expectRevert("RentToken: Contributor is sanctioned");
        rentToken.contribute(50_000 * 1e6);
        vm.stopPrank();
    }

    function test_Contribute_WrongPhase() public {
        // Move past fundraising phase
        vm.warp(testProperty.accrualStart + 1);

        vm.startPrank(user1);
        usdc.approve(address(rentToken), 50_000 * 1e6);

        vm.expectRevert("RentToken: Wrong phase");
        rentToken.contribute(50_000 * 1e6);
        vm.stopPrank();
    }

    // ========== 利润分发测试 ==========

    function test_ReceiveProfit_Success() public {
        // Setup: contribute to meet minimum and move to running phase
        vm.startPrank(user1);
        usdc.approve(address(rentToken), testProperty.minRaising);
        rentToken.contribute(testProperty.minRaising);
        vm.stopPrank();

        vm.warp(testProperty.accrualStart + 1);

        uint256 profitAmount = 5000 * 1e6;

        vm.startPrank(address(factory));
        usdc.approve(address(rentToken), profitAmount);

        vm.expectEmit(false, false, false, true);
        emit ProfitReceived(profitAmount, profitAmount * 1e18 / testProperty.minRaising);

        rentToken.receiveProfit(profitAmount);
        vm.stopPrank();

        assertEq(rentToken.totalProfitReceived(), profitAmount);
        assertGt(rentToken.accumulatedRewardPerToken(), 0);
    }

    function test_ReceiveProfit_OnlyFactory() public {
        vm.startPrank(user1);
        vm.expectRevert("RentToken: Only SeriesFactory can call");
        rentToken.receiveProfit(1000 * 1e6);
        vm.stopPrank();
    }

    function test_Claim_Success() public {
        // Setup: contribute and receive profit
        uint256 contribution = testProperty.minRaising;
        vm.startPrank(user1);
        usdc.approve(address(rentToken), contribution);
        rentToken.contribute(contribution);
        vm.stopPrank();

        vm.warp(testProperty.accrualStart + 1);

        uint256 profitAmount = 5000 * 1e6;
        vm.startPrank(address(factory));
        usdc.approve(address(rentToken), profitAmount);
        rentToken.receiveProfit(profitAmount);
        vm.stopPrank();

        // User claims profit
        uint256 claimableAmount = rentToken.getClaimableAmount(user1);
        assertEq(claimableAmount, profitAmount); // User owns 100% of tokens

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.startPrank(user1);
        vm.expectEmit(true, false, false, true);
        emit ProfitClaimed(user1, claimableAmount);

        rentToken.claim();
        vm.stopPrank();

        uint256 balanceAfter = usdc.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, claimableAmount);
        assertEq(rentToken.getClaimableAmount(user1), 0);
    }

    function test_Claim_MultipleUsers() public {
        uint256 amount1 = 60_000 * 1e6;
        uint256 amount2 = 40_000 * 1e6;
        uint256 totalContribution = amount1 + amount2;

        // Users contribute
        vm.startPrank(user1);
        usdc.approve(address(rentToken), amount1);
        rentToken.contribute(amount1);
        vm.stopPrank();

        vm.startPrank(user2);
        usdc.approve(address(rentToken), amount2);
        rentToken.contribute(amount2);
        vm.stopPrank();

        vm.warp(testProperty.accrualStart + 1);

        uint256 profitAmount = 10_000 * 1e6;
        vm.startPrank(address(factory));
        usdc.approve(address(rentToken), profitAmount);
        rentToken.receiveProfit(profitAmount);
        vm.stopPrank();

        // Check claimable amounts
        uint256 expectedUser1 = profitAmount * amount1 / totalContribution;
        uint256 expectedUser2 = profitAmount * amount2 / totalContribution;

        assertEq(rentToken.getClaimableAmount(user1), expectedUser1);
        assertEq(rentToken.getClaimableAmount(user2), expectedUser2);

        // Users claim
        vm.prank(user1);
        rentToken.claim();

        vm.prank(user2);
        rentToken.claim();

        assertEq(rentToken.getClaimableAmount(user1), 0);
        assertEq(rentToken.getClaimableAmount(user2), 0);
    }

    // ========== 退款测试 ==========

    function test_Refund_Success() public {
        uint256 amount = 50_000 * 1e6;

        // User contributes
        vm.startPrank(user1);
        usdc.approve(address(rentToken), amount);
        rentToken.contribute(amount);
        vm.stopPrank();

        // Move past accrual start without meeting minimum (fundraising failed)
        vm.warp(testProperty.accrualStart + 1);

        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.startPrank(user1);
        vm.expectEmit(true, false, false, true);
        emit RefundProcessed(user1, amount);

        rentToken.refund();
        vm.stopPrank();

        uint256 balanceAfter = usdc.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, amount);
        assertEq(rentToken.balanceOf(user1), 0);
    }

    function test_Refund_WrongPhase() public {
        vm.startPrank(user1);
        vm.expectRevert("RentToken: Wrong phase");
        rentToken.refund();
        vm.stopPrank();
    }

    function test_Refund_NoBalance() public {
        // Move to fundraising failed phase
        vm.warp(testProperty.accrualStart + 1);

        vm.startPrank(user1);
        vm.expectRevert("RentToken: No tokens to refund");
        rentToken.refund();
        vm.stopPrank();
    }

    // ========== 代币转移测试 ==========

    function test_Transfer_Success() public {
        uint256 amount = testProperty.minRaising;

        // User1 contributes to meet minimum raising
        vm.startPrank(user1);
        usdc.approve(address(rentToken), amount);
        rentToken.contribute(amount);
        vm.stopPrank();

        // Move to accrual phase to allow transfers
        vm.warp(testProperty.accrualStart + 1);

        // Transfer to user2
        vm.startPrank(user1);
        rentToken.transfer(user2, amount / 2);
        vm.stopPrank();

        assertEq(rentToken.balanceOf(user1), amount / 2);
        assertEq(rentToken.balanceOf(user2), amount / 2);
    }

    function test_Transfer_ToSanctionedUser() public {
        uint256 amount = 50_000 * 1e6;

        vm.startPrank(user1);
        usdc.approve(address(rentToken), amount);
        rentToken.contribute(amount);
        vm.stopPrank();

        sanctionOracle.setBlocked(user2, true);

        vm.startPrank(user1);
        vm.expectRevert("RentToken: Recipient is sanctioned");
        rentToken.transfer(user2, amount / 2);
        vm.stopPrank();
    }

    // ========== 管理功能测试 ==========

    function test_Pause_Success() public {
        // Transfer ownership to admin for testing
        vm.prank(address(factory));
        rentToken.transferOwnership(admin);

        rentToken.pause();
        assertTrue(rentToken.paused());

        vm.startPrank(user1);
        usdc.approve(address(rentToken), 50_000 * 1e6);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        rentToken.contribute(50_000 * 1e6);
        vm.stopPrank();
    }

    function test_WithdrawRemainingFunds_Success() public {
        uint256 amount = 50_000 * 1e6;

        // Transfer ownership to admin for testing
        vm.prank(address(factory));
        rentToken.transferOwnership(admin);

        // Contribute and move to terminated phase (180 days after accrual end)
        vm.startPrank(user1);
        usdc.approve(address(rentToken), testProperty.minRaising);
        rentToken.contribute(testProperty.minRaising);
        vm.stopPrank();

        vm.warp(testProperty.accrualEnd + 181 days);

        // Add some remaining funds
        usdc.transfer(address(rentToken), amount);

        uint256 balanceBefore = usdc.balanceOf(admin);
        rentToken.withdrawRemainingFunds();
        uint256 balanceAfter = usdc.balanceOf(admin);

        // Should withdraw both the contributed amount and the additional funds
        assertEq(balanceAfter - balanceBefore, testProperty.minRaising + amount);
    }

    function test_WithdrawRemainingFunds_WrongPhase() public {
        // Transfer ownership to admin for testing
        vm.prank(address(factory));
        rentToken.transferOwnership(admin);

        vm.expectRevert("RentToken: Not terminated yet");
        rentToken.withdrawRemainingFunds();
    }

    // ========== 边界条件测试 ==========

    function test_Contribute_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("RentToken: Amount must be positive");
        rentToken.contribute(0);
        vm.stopPrank();
    }

    function test_Contribute_ExactMaxRaising() public {
        vm.startPrank(user1);
        usdc.approve(address(rentToken), testProperty.maxRaising);
        rentToken.contribute(testProperty.maxRaising);
        vm.stopPrank();

        assertEq(rentToken.totalFundRaised(), testProperty.maxRaising);
        assertEq(rentToken.balanceOf(user1), testProperty.maxRaising);
    }

    function test_MultipleSmallContributions() public {
        uint256 smallAmount = 1000 * 1e6;
        uint256 numContributions = 10;

        vm.startPrank(user1);
        for (uint256 i = 0; i < numContributions; i++) {
            usdc.approve(address(rentToken), smallAmount);
            rentToken.contribute(smallAmount);
        }
        vm.stopPrank();

        assertEq(rentToken.balanceOf(user1), smallAmount * numContributions);
        assertEq(rentToken.totalFundRaised(), smallAmount * numContributions);
    }
}
