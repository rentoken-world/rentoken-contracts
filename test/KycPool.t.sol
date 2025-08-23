// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../src/ammpool/KycPool.sol";
import "../src/ammpool/KycPoolFactory.sol";
import "../src/KYCOracle.sol";
import "../src/mocks/MockUSDC.sol";

// Mock RentToken for testing (6 decimals)
contract MockRTN {
    string public name = "Mock RentToken";
    string public symbol = "mRTN";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        _mint(msg.sender, 1000000000000); // 1M RTN with 6 decimals
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(balanceOf[from] >= amount, "Insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract KycPoolTest is Test {
    KycPool public pool;
    KycPoolFactory public factory;
    KYCOracle public kycOracle;
    MockRTN public rtn;
    MockUSDC public usdc;

    address public admin;
    address public lpProvider;
    address public userA;
    address public userB;
    address public nonKYCUser;

    uint256 public constant PROPERTY_ID = 1;
    uint16 public constant DEFAULT_FEE_BPS = 30; // 0.3%

    // Helper amounts (6 decimals)
    uint256 public constant RTN_LIQUIDITY = 10_000e6;  // 10,000 RTN
    uint256 public constant USDC_LIQUIDITY = 10_000e6; // 10,000 USDC
    uint256 public constant SWAP_RTN_AMOUNT = 1_000e6;  // 1,000 RTN
    uint256 public constant SWAP_USDC_AMOUNT = 500e6;   // 500 USDC

    event PoolCreated(uint256 indexed propertyId, address pool, address rtk, address usdc, uint16 feeBps);
    event MintShares(address indexed provider, uint256 shares, uint256 amtRTN, uint256 amtUSDC);
    event BurnShares(address indexed provider, uint256 shares, uint256 amtRTN, uint256 amtUSDC, address to);
    event Swap(address indexed sender, bool rtIn, uint256 amtIn, uint256 amtOut, address to);
    event TradingOpened(bool open);

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        lpProvider = makeAddr("lpProvider");
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        nonKYCUser = makeAddr("nonKYCUser");

        // Deploy contracts
        vm.startPrank(admin);

        kycOracle = new KYCOracle();
        rtn = new MockRTN();
        usdc = new MockUSDC();
        factory = new KycPoolFactory(address(kycOracle), admin);

        // Create pool through factory
        address poolAddr = factory.createPool(PROPERTY_ID, address(rtn), address(usdc), DEFAULT_FEE_BPS);
        pool = KycPool(poolAddr);

        // Verify pool creation
        assertEq(factory.poolOf(PROPERTY_ID), address(pool));
        assertEq(pool.rtk(), address(rtn));
        assertEq(pool.usdc(), address(usdc));
        assertEq(pool.feeBps(), DEFAULT_FEE_BPS);

        // Add addresses to KYC whitelist (admin is the owner of KYCOracle)
        kycOracle.addToWhitelist(lpProvider);
        kycOracle.addToWhitelist(userA);
        kycOracle.addToWhitelist(userB);
        kycOracle.addToWhitelist(address(pool));

        // Open trading (directly on pool since admin is the pool admin)
        pool.openTrading();
        assertTrue(pool.isOpen());

        vm.stopPrank();

        // Distribute tokens
        _distributeTokens();

    }

    function _distributeTokens() private {
        // Mint and distribute tokens
        rtn.mint(lpProvider, RTN_LIQUIDITY * 2);
        rtn.mint(userA, SWAP_RTN_AMOUNT * 2);
        usdc.mint(lpProvider, USDC_LIQUIDITY * 2);
        usdc.mint(userB, SWAP_USDC_AMOUNT * 2);
    }

    function testKYCGating() public {
        // Test KYC requirements for adding liquidity
        vm.startPrank(nonKYCUser);
        rtn.mint(nonKYCUser, RTN_LIQUIDITY);
        usdc.mint(nonKYCUser, USDC_LIQUIDITY);

        rtn.approve(address(pool), RTN_LIQUIDITY);
        usdc.approve(address(pool), USDC_LIQUIDITY);

        vm.expectRevert("KYC_REQUIRED");
        pool.addLiquidity(RTN_LIQUIDITY, USDC_LIQUIDITY, 0, block.timestamp + 1);
        vm.stopPrank();

        console.log("[OK] KYC gating works for add liquidity");
    }

    function testTradingControl() public {
        // Test that trading can be closed (directly on pool since factory lacks permission)
        vm.prank(admin);
        pool.closeTrading();
        assertFalse(pool.isOpen());

        vm.startPrank(lpProvider);
        rtn.approve(address(pool), RTN_LIQUIDITY);
        usdc.approve(address(pool), USDC_LIQUIDITY);

        vm.expectRevert("CLOSED");
        pool.addLiquidity(RTN_LIQUIDITY, USDC_LIQUIDITY, 0, block.timestamp + 1);
        vm.stopPrank();

        // Reopen trading for other tests (directly on pool)
        vm.prank(admin);
        pool.openTrading();

        console.log("[OK] Trading control works");
    }

    function testAddLiquidity() public {
        vm.startPrank(lpProvider);

        // Approve tokens
        rtn.approve(address(pool), RTN_LIQUIDITY);
        usdc.approve(address(pool), USDC_LIQUIDITY);

        // Add liquidity
        uint256 newShares = pool.addLiquidity(
            RTN_LIQUIDITY,
            USDC_LIQUIDITY,
            0, // minShares
            block.timestamp + 1
        );

        // Check reserves
        (uint112 reserveRTN, uint112 reserveUSDC,) = pool.getReserves();
        assertEq(uint256(reserveRTN), RTN_LIQUIDITY);
        assertEq(uint256(reserveUSDC), USDC_LIQUIDITY);

        // Check shares (first liquidity should be sqrt(rtn * usdc) - MIN_LIQUIDITY)
        uint256 expectedShares = sqrt(RTN_LIQUIDITY * USDC_LIQUIDITY) - 1000; // MIN_LIQUIDITY = 1000
        assertEq(newShares, expectedShares);
        assertEq(pool.shares(lpProvider), expectedShares);
        assertEq(pool.totalShares(), expectedShares + 1000); // Including locked liquidity

        vm.stopPrank();

        console.log("[OK] Add liquidity works");
        console.log("New shares minted:", newShares);
        console.log("Reserve RTN:", uint256(reserveRTN));
        console.log("Reserve USDC:", uint256(reserveUSDC));
    }

    function testSwapRTNForUSDC() public {
        // First add liquidity
        testAddLiquidity();

        vm.startPrank(userA);

        // Approve RTN
        rtn.approve(address(pool), SWAP_RTN_AMOUNT);

        // Get expected output
        (uint112 reserveRTN, uint112 reserveUSDC,) = pool.getReserves();
        uint256 expectedOut = pool.getAmountOut(SWAP_RTN_AMOUNT, uint256(reserveRTN), uint256(reserveUSDC));

        console.log("Expected USDC out:", expectedOut);

        // Perform swap
        uint256 outUSDC = pool.swapExactRTNForUSDC(
            SWAP_RTN_AMOUNT,
            expectedOut - 1, // Allow 1 unit slippage
            userA,
            block.timestamp + 1
        );

        // Verify output
        assertApproxEqAbs(outUSDC, expectedOut, 1);

        // Check balances
        assertEq(usdc.balanceOf(userA), outUSDC);

        vm.stopPrank();

        console.log("[OK] Swap RTN for USDC works");
        console.log("RTN in:", SWAP_RTN_AMOUNT);
        console.log("USDC out:", outUSDC);
    }

    function testSwapUSDCForRTN() public {
        // First add liquidity
        testAddLiquidity();

        vm.startPrank(userB);

        // Approve USDC
        usdc.approve(address(pool), SWAP_USDC_AMOUNT);

        // Get expected output
        (uint112 reserveRTN, uint112 reserveUSDC,) = pool.getReserves();
        uint256 expectedOut = pool.getAmountOut(SWAP_USDC_AMOUNT, uint256(reserveUSDC), uint256(reserveRTN));

        console.log("Expected RTN out:", expectedOut);

        // Perform swap
        uint256 outRTN = pool.swapExactUSDCForRTN(
            SWAP_USDC_AMOUNT,
            expectedOut - 1, // Allow 1 unit slippage
            userB,
            block.timestamp + 1
        );

        // Verify output
        assertApproxEqAbs(outRTN, expectedOut, 1);

        // Check balances
        assertEq(rtn.balanceOf(userB), outRTN);

        vm.stopPrank();

        console.log("[OK] Swap USDC for RTN works");
        console.log("USDC in:", SWAP_USDC_AMOUNT);
        console.log("RTN out:", outRTN);
    }

    function testRemoveLiquidity() public {
        // First add liquidity
        testAddLiquidity();

        vm.startPrank(lpProvider);

        uint256 currentShares = pool.shares(lpProvider);
        uint256 sharesToRemove = currentShares / 2; // Remove half

        // Get expected output
        (uint112 reserveRTN, uint112 reserveUSDC,) = pool.getReserves();
        uint256 totalShares = pool.totalShares();

        uint256 balanceRTN = rtn.balanceOf(address(pool));
        uint256 balanceUSDC = usdc.balanceOf(address(pool));

        uint256 expectedRTN = (sharesToRemove * balanceRTN) / totalShares;
        uint256 expectedUSDC = (sharesToRemove * balanceUSDC) / totalShares;

        // Remove liquidity
        (uint256 outRTN, uint256 outUSDC) = pool.removeLiquidity(
            sharesToRemove,
            expectedRTN - 1, // Allow 1 unit slippage
            expectedUSDC - 1, // Allow 1 unit slippage
            block.timestamp + 1
        );

        // Verify outputs
        assertApproxEqAbs(outRTN, expectedRTN, 1);
        assertApproxEqAbs(outUSDC, expectedUSDC, 1);

        // Check shares
        assertEq(pool.shares(lpProvider), currentShares - sharesToRemove);

        vm.stopPrank();

        console.log("[OK] Remove liquidity works");
        console.log("Shares removed:", sharesToRemove);
        console.log("RTN returned:", outRTN);
        console.log("USDC returned:", outUSDC);
    }

    function testSwapKYCToAddress() public {
        // First add liquidity
        testAddLiquidity();

        vm.startPrank(userA);

        rtn.approve(address(pool), SWAP_RTN_AMOUNT);

        // Try to swap to non-KYC address - should revert
        vm.expectRevert("KYC_REQUIRED");
        pool.swapExactRTNForUSDC(
            SWAP_RTN_AMOUNT,
            0,
            nonKYCUser, // Non-KYC address
            block.timestamp + 1
        );

        vm.stopPrank();

        console.log("[OK] Swap KYC gating for 'to' address works");
    }

    function testDeadlineCheck() public {
        // First add liquidity
        testAddLiquidity();

        vm.startPrank(userA);

        rtn.approve(address(pool), SWAP_RTN_AMOUNT);

        // Try with expired deadline
        vm.expectRevert("EXPIRED");
        pool.swapExactRTNForUSDC(
            SWAP_RTN_AMOUNT,
            0,
            userA,
            block.timestamp - 1 // Expired
        );

        vm.stopPrank();

        console.log("[OK] Deadline check works");
    }

    function testSlippageProtection() public {
        // First add liquidity
        testAddLiquidity();

        vm.startPrank(userA);

        rtn.approve(address(pool), SWAP_RTN_AMOUNT);

        // Get expected output
        (uint112 reserveRTN, uint112 reserveUSDC,) = pool.getReserves();
        uint256 expectedOut = pool.getAmountOut(SWAP_RTN_AMOUNT, uint256(reserveRTN), uint256(reserveUSDC));

        // Try with too high minOut
        vm.expectRevert("SLIPPAGE");
        pool.swapExactRTNForUSDC(
            SWAP_RTN_AMOUNT,
            expectedOut + 1000, // Too high
            userA,
            block.timestamp + 1
        );

        vm.stopPrank();

        console.log("[OK] Slippage protection works");
    }

    function testPauseFunctionality() public {
        // First add liquidity
        testAddLiquidity();

        // Pause the contract
        vm.prank(admin);
        pool.pause();

        vm.startPrank(userA);
        rtn.approve(address(pool), SWAP_RTN_AMOUNT);

        // Try to swap while paused - should revert (OpenZeppelin v5 uses custom errors)
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        pool.swapExactRTNForUSDC(
            SWAP_RTN_AMOUNT,
            0,
            userA,
            block.timestamp + 1
        );

        vm.stopPrank();

        // Unpause
        vm.prank(admin);
        pool.unpause();

        console.log("[OK] Pause functionality works");
    }

    function testFeeBpsAdjustment() public {
        // Test fee adjustment
        vm.prank(admin);
        pool.setFeeBps(50); // 0.5%

        assertEq(pool.feeBps(), 50);

        // Test that fee too high reverts
        vm.prank(admin);
        vm.expectRevert("FEE_TOO_HIGH");
        pool.setFeeBps(101);

        console.log("[OK] Fee adjustment works");
    }

    function testPoolPricing() public {
        // First add liquidity
        testAddLiquidity();

        // Check prices
        uint256 priceRTNinUSDC = pool.getPriceRTNinUSDC();
        uint256 priceUSDCinRTN = pool.getPriceUSDCinRTN();

        // Since we added equal amounts, price should be approximately 1:1 (in 6 decimal terms)
        assertEq(priceRTNinUSDC, 1e6); // 1 RTN = 1 USDC
        assertEq(priceUSDCinRTN, 1e6); // 1 USDC = 1 RTN

        console.log("[OK] Pricing functions work");
        console.log("Price RTN in USDC:", priceRTNinUSDC);
        console.log("Price USDC in RTN:", priceUSDCinRTN);
    }

    function testQuoteFunctions() public {
        // First add liquidity
        testAddLiquidity();

        (uint112 reserveRTN, uint112 reserveUSDC,) = pool.getReserves();

        // Test quote function
        uint256 quoted = pool.quote(1000e6, uint256(reserveRTN), uint256(reserveUSDC));
        assertEq(quoted, 1000e6); // Should be equal since reserves are equal

        // Test getAmountOut with fees
        uint256 amountOut = pool.getAmountOut(1000e6, uint256(reserveRTN), uint256(reserveUSDC));
        assertTrue(amountOut < quoted); // Should be less due to fees

        // Test getAmountIn
        uint256 amountIn = pool.getAmountIn(amountOut, uint256(reserveRTN), uint256(reserveUSDC));
        assertApproxEqAbs(amountIn, 1000e6, 1); // Should be approximately the input amount

        console.log("[OK] Quote functions work");
        console.log("Quote (no fee):", quoted);
        console.log("Amount out (with fee):", amountOut);
        console.log("Amount in (reverse):", amountIn);
    }

    // Helper function for sqrt calculation (same as in pool contract)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
