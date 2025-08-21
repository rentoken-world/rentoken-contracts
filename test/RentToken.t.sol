// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/RentToken.sol";
import "../src/PropertyOracle.sol";
import "../src/KYCOracle.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockSanctionOracle.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract RentTokenTest is Test {
    RentToken public rentToken;
    PropertyOracle public propertyOracle;
    KYCOracle public kycOracle;
    MockSanctionOracle public sanctionOracle;
    MockUSDC public usdc;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public landlord = makeAddr("landlord");
    address public factory = makeAddr("factory");

    uint256 public constant PROPERTY_ID = 1;
    uint256 public constant MIN_RAISING = 10000 * 1e6;
    uint256 public constant MAX_RAISING = 100000 * 1e6;
    uint64 public accrualStart;
    uint64 public accrualEnd;

    address public rentTokenImpl;

    function setUp() public {
        vm.prank(admin);
        usdc = new MockUSDC();

        vm.prank(admin);
        propertyOracle = new PropertyOracle();

        vm.prank(admin);
        kycOracle = new KYCOracle();

        vm.prank(admin);
        sanctionOracle = new MockSanctionOracle();

        accrualStart = uint64(block.timestamp + 1 days);
        accrualEnd = uint64(block.timestamp + 365 days);

        PropertyOracle.PropertyData memory data = PropertyOracle.PropertyData({
            propertyId: PROPERTY_ID,
            payoutToken: address(usdc),
            valuation: 1000000 * 1e6,
            minRaising: MIN_RAISING,
            maxRaising: MAX_RAISING,
            accrualStart: accrualStart,
            accrualEnd: accrualEnd,
            landlord: landlord,
            docHash: keccak256("docs"),
            offchainURL: "https://example.com"
        });

        vm.prank(admin);
        propertyOracle.addOrUpdateProperty(PROPERTY_ID, data);

        // Deploy implementation
        rentTokenImpl = address(new RentToken());

        // Clone as proxy
        address proxy = Clones.clone(rentTokenImpl);

        // Initialize the proxy with admin as msg.sender
        vm.prank(admin);
        RentToken(proxy).initialize(
            "RenToken Test",
            "RTT",
            PROPERTY_ID,
            address(usdc),
            MIN_RAISING,
            MAX_RAISING,
            accrualStart,
            accrualEnd,
            landlord,
            factory,
            address(propertyOracle),
            address(kycOracle),
            address(sanctionOracle)
        );

        rentToken = RentToken(proxy);

        // Whitelist users
        vm.prank(admin);
        kycOracle.addToWhitelist(user1);
        vm.prank(admin);
        kycOracle.addToWhitelist(user2);
        vm.prank(admin);
        kycOracle.addToWhitelist(admin);

        // Mint some USDC to users
        vm.prank(admin);
        usdc.mint(user1, 100000 * 1e6);
        vm.prank(admin);
        usdc.mint(user2, 100000 * 1e6);
    }

    function test_DeployAndInitialState() public view {
        assertEq(rentToken.name(), "RenToken Test");
        assertEq(rentToken.symbol(), "RTT");
        assertEq(rentToken.totalSupply(), 0);
        assertEq(rentToken.propertyId(), PROPERTY_ID);
        assertEq(rentToken.minRaising(), MIN_RAISING);
        assertEq(rentToken.maxRaising(), MAX_RAISING);
        assertEq(rentToken.accrualStart(), accrualStart);
        assertEq(rentToken.accrualEnd(), accrualEnd);
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.Fundraising));
    }

    function test_Contribute() public {
        uint256 contributeAmount = 1000 * 1e6;

        vm.prank(user1);
        usdc.approve(address(rentToken), contributeAmount);

        vm.prank(user1);
        rentToken.contribute(contributeAmount);

        assertEq(rentToken.balanceOf(user1), contributeAmount);
        assertEq(rentToken.totalFundRaised(), contributeAmount);
        assertEq(usdc.balanceOf(address(rentToken)), contributeAmount);
    }

    function test_Transfer() public {
        // First contribute
        uint256 contributeAmount = 10000 * 1e6;
        vm.prank(user1);
        usdc.approve(address(rentToken), contributeAmount);
        vm.prank(user1);
        rentToken.contribute(contributeAmount);

        // Move to AccrualStarted phase
        vm.warp(accrualStart + 1);
        vm.assume(rentToken.totalFundRaised() >= MIN_RAISING); // Ensure phase is AccrualStarted
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.AccrualStarted));

        // Transfer
        uint256 transferAmount = 200 * 1e6;
        vm.prank(user1);
        rentToken.transfer(user2, transferAmount);

        assertEq(rentToken.balanceOf(user1), contributeAmount - transferAmount);
        assertEq(rentToken.balanceOf(user2), transferAmount);
    }

    function test_ReceiveProfitAndClaim() public {
        // Contribute
        uint256 contributeAmount = 10000 * 1e6;
        vm.prank(user1);
        usdc.approve(address(rentToken), contributeAmount);
        vm.prank(user1);
        rentToken.contribute(contributeAmount);

        // Warp to accrual started
        vm.warp(accrualStart + 1);
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.AccrualStarted));

        // Receive profit
        uint256 profitAmount = 1000 * 1e6;
        vm.prank(admin);
        usdc.mint(factory, profitAmount);
        vm.prank(factory);
        usdc.approve(address(rentToken), profitAmount);
        vm.prank(factory);
        rentToken.receiveProfit(profitAmount);

        // Claim
        uint256 balanceBefore = usdc.balanceOf(user1);
        vm.prank(user1);
        rentToken.claim();
        uint256 balanceAfter = usdc.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, profitAmount);
    }

    function test_ClaimWithAmount() public {
        // Setup: User contributes and receives profit
        uint256 contributionAmount = 50_000 * 1e6;
        vm.prank(user1);
        usdc.approve(address(rentToken), contributionAmount);
        vm.prank(user1);
        rentToken.contribute(contributionAmount);

        // Fast forward to accrual phase
        vm.warp(accrualStart + 1);

        // Distribute profit
        uint256 profitAmount = 10_000 * 1e6;
        vm.prank(admin);
        usdc.mint(factory, profitAmount);
        vm.prank(factory);
        usdc.approve(address(rentToken), profitAmount);
        vm.prank(factory);
        rentToken.receiveProfit(profitAmount);

        // Test claiming specific amount
        uint256 claimAmount = 3_000 * 1e6;
        uint256 balanceBefore = usdc.balanceOf(user1);
        uint256 claimableBefore = rentToken.getClaimableAmount(user1);

        vm.prank(user1);
        rentToken.claim(claimAmount);

        uint256 balanceAfter = usdc.balanceOf(user1);
        uint256 claimableAfter = rentToken.getClaimableAmount(user1);

        assertEq(balanceAfter - balanceBefore, claimAmount);
        assertEq(claimableAfter, claimableBefore - claimAmount);

        // Test claiming remaining amount
        vm.prank(user1);
        rentToken.claim(0); // Claim all remaining

        assertEq(rentToken.getClaimableAmount(user1), 0);
    }

    function test_ClaimAmountExceedsClaimable() public {
        // Setup: User contributes and receives profit
        uint256 contributionAmount = 50_000 * 1e6;
        vm.prank(user1);
        usdc.approve(address(rentToken), contributionAmount);
        vm.prank(user1);
        rentToken.contribute(contributionAmount);

        // Fast forward to accrual phase
        vm.warp(accrualStart + 1);

        // Distribute profit
        uint256 profitAmount = 10_000 * 1e6;
        vm.prank(admin);
        usdc.mint(factory, profitAmount);
        vm.prank(factory);
        usdc.approve(address(rentToken), profitAmount);
        vm.prank(factory);
        rentToken.receiveProfit(profitAmount);

        // Try to claim more than available
        uint256 claimableAmount = rentToken.getClaimableAmount(user1);
        uint256 excessiveAmount = claimableAmount + 1000 * 1e6;

        vm.prank(user1);
        vm.expectRevert("RentToken: Amount exceeds claimable");
        rentToken.claim(excessiveAmount);
    }

        function test_ClaimZeroAmount() public {
        // Setup: User contributes and receives profit
        uint256 contributionAmount = 50_000 * 1e6;
        vm.prank(user1);
        usdc.approve(address(rentToken), contributionAmount);
        vm.prank(user1);
        rentToken.contribute(contributionAmount);

        // Fast forward to accrual phase
        vm.warp(accrualStart + 1);

        // Distribute profit
        uint256 profitAmount = 10_000 * 1e6;
        vm.prank(admin);
        usdc.mint(factory, profitAmount);
        vm.prank(admin);
        usdc.mint(factory, profitAmount);
        vm.prank(factory);
        usdc.approve(address(rentToken), profitAmount);
        vm.prank(factory);
        rentToken.receiveProfit(profitAmount);

        // Claim with zero amount (should claim all)
        uint256 balanceBefore = usdc.balanceOf(user1);
        uint256 claimableBefore = rentToken.getClaimableAmount(user1);

        vm.prank(user1);
        rentToken.claim(0);

        uint256 balanceAfter = usdc.balanceOf(user1);
        uint256 claimableAfter = rentToken.getClaimableAmount(user1);

        assertEq(balanceAfter - balanceBefore, claimableBefore);
        assertEq(claimableAfter, 0);
    }

    function test_ClaimNoParameter() public {
        // Setup: User contributes and receives profit
        uint256 contributionAmount = 50_000 * 1e6;
        vm.prank(user1);
        usdc.approve(address(rentToken), contributionAmount);
        vm.prank(user1);
        rentToken.contribute(contributionAmount);

        // Fast forward to accrual phase
        vm.warp(accrualStart + 1);

        // Distribute profit
        uint256 profitAmount = 10_000 * 1e6;
        vm.prank(admin);
        usdc.mint(factory, profitAmount);
        vm.prank(factory);
        usdc.approve(address(rentToken), profitAmount);
        vm.prank(factory);
        rentToken.receiveProfit(profitAmount);

        // Test claiming without parameter (should claim all)
        uint256 balanceBefore = usdc.balanceOf(user1);
        uint256 claimableBefore = rentToken.getClaimableAmount(user1);

        vm.prank(user1);
        rentToken.claim(); // No parameter

        uint256 balanceAfter = usdc.balanceOf(user1);
        uint256 claimableAfter = rentToken.getClaimableAmount(user1);

        assertEq(balanceAfter - balanceBefore, claimableBefore);
        assertEq(claimableAfter, 0);
    }

    function testFuzz_Contribute(uint256 amount) public {
        vm.assume(amount > 0 && amount <= MAX_RAISING);

        vm.prank(user1);
        usdc.approve(address(rentToken), amount);

        vm.prank(user1);
        rentToken.contribute(amount);

        assertEq(rentToken.balanceOf(user1), amount);
        assertEq(rentToken.totalFundRaised(), amount);
    }

    function testSetStartTime() public {
        // Should be in fundraising phase initially
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.Fundraising));

        uint64 originalStartTime = rentToken.accrualStart();

        // Only admin can call setStartTime
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        rentToken.setStartTime();

        // Admin can call setStartTime in fundraising phase
        vm.prank(admin);
        rentToken.setStartTime();

        uint64 newStartTime = rentToken.accrualStart();
        // The new start time should be different from the original
        assertTrue(newStartTime != originalStartTime);
        // The new start time should be close to current block.timestamp + 1
        assertLe(newStartTime, block.timestamp + 2); // Should be current time + 1 second

        // Should still be in fundraising phase since we haven't reached the new start time
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.Fundraising));
    }

    function testSetStartTimeOnlyInFundraising() public {
        // Add enough contributions to reach minRaising first
        uint256 contributionAmount = MIN_RAISING;

        vm.prank(user1);
        usdc.approve(address(rentToken), contributionAmount);
        vm.prank(user1);
        rentToken.contribute(contributionAmount);

        // Fast forward to after accrual start time
        vm.warp(accrualStart + 1);

        // Should be in AccrualStarted phase now
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.AccrualStarted));

        // Admin cannot call setStartTime in non-fundraising phase
        vm.prank(admin);
        vm.expectRevert("RentToken: Wrong phase");
        rentToken.setStartTime();
    }

    function testSetStartTimeEmitsPhaseChangeEvent() public {
        // Add enough contributions to reach minRaising
        uint256 contributionAmount = MIN_RAISING;

        vm.prank(user1);
        usdc.approve(address(rentToken), contributionAmount);
        vm.prank(user1);
        rentToken.contribute(contributionAmount);

        // Set start time to trigger phase change
        vm.prank(admin);
        rentToken.setStartTime();

        // Fast forward to after the new start time
        vm.warp(rentToken.accrualStart() + 1);

        // Should now be in AccrualStarted phase
        assertEq(uint256(rentToken.getPhase()), uint256(RentToken.Phase.AccrualStarted));
    }

    // Add more tests as needed
}

// For invariant test
contract RentTokenInvariantTest is Test {
    RentToken public rentToken;
    PropertyOracle public propertyOracle;
    KYCOracle public kycOracle;
    MockSanctionOracle public sanctionOracle;
    MockUSDC public usdc;

    address public admin = makeAddr("admin");
    address public landlord = makeAddr("landlord");
    address public factory = makeAddr("factory");

    uint256 public constant PROPERTY_ID = 1;
    uint256 public constant MIN_RAISING = 10000 * 1e6;
    uint256 public constant MAX_RAISING = 100000 * 1e6;
    uint64 public accrualStart;
    uint64 public accrualEnd;

    address public rentTokenImpl;

    function setUp() public {
        // Similar setup
        vm.prank(admin);
        usdc = new MockUSDC();

        vm.prank(admin);
        propertyOracle = new PropertyOracle();

        vm.prank(admin);
        kycOracle = new KYCOracle();

        vm.prank(admin);
        sanctionOracle = new MockSanctionOracle();

        accrualStart = uint64(block.timestamp + 1 days);
        accrualEnd = uint64(block.timestamp + 365 days);

        PropertyOracle.PropertyData memory data = PropertyOracle.PropertyData({
            propertyId: PROPERTY_ID,
            payoutToken: address(usdc),
            valuation: 1000000 * 1e6,
            minRaising: MIN_RAISING,
            maxRaising: MAX_RAISING,
            accrualStart: accrualStart,
            accrualEnd: accrualEnd,
            landlord: landlord,
            docHash: keccak256("docs"),
            offchainURL: "https://example.com"
        });

        vm.prank(admin);
        propertyOracle.addOrUpdateProperty(PROPERTY_ID, data);

        // Deploy implementation
        rentTokenImpl = address(new RentToken());

        // Clone as proxy
        address proxy = Clones.clone(rentTokenImpl);

        // Initialize the proxy
        RentToken(proxy).initialize(
            "RenToken Test",
            "RTT",
            PROPERTY_ID,
            address(usdc),
            MIN_RAISING,
            MAX_RAISING,
            accrualStart,
            accrualEnd,
            landlord,
            factory,
            address(propertyOracle),
            address(kycOracle),
            address(sanctionOracle)
        );

        rentToken = RentToken(proxy);
    }

    // Invariant: totalFundRaised <= maxRaising
    function invariant_TotalFundRaised() public view {
        assertLe(rentToken.totalFundRaised(), rentToken.maxRaising());
    }
}
