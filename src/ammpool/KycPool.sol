// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title KYC Oracle Interface
 */
interface IKYCOracle {
    function isWhitelisted(address account) external view returns (bool);
}

/**
 * @title ERC20 Decimals Interface
 */
interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

/**
 * @title KycPool Contract
 * @dev KYC version of Uniswap v2 constant product pool for RTN <-> USDC
 */
contract KycPool is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant MIN_LIQUIDITY = 1000;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Immutable tokens
    address public immutable rtk;
    address public immutable usdc;

    // Oracle and settings
    IKYCOracle public kyc;
    uint16 public feeBps; // 0-100 (0-1.00%)

    // Reserves (using smaller storage slots for gas efficiency)
    uint112 private reserveRTN;
    uint112 private reserveUSDC;
    uint32 private blockTimestampLast;

    // LP shares (non-transferable)
    mapping(address => uint256) public shares;
    uint256 public totalShares;

    // Trading control
    bool public isOpen;

    // Events
    event PoolSynced(uint112 reserveRTN, uint112 reserveUSDC);
    event MintShares(address indexed provider, uint256 shares, uint256 amtRTN, uint256 amtUSDC);
    event BurnShares(address indexed provider, uint256 shares, uint256 amtRTN, uint256 amtUSDC, address to);
    event Swap(address indexed sender, bool rtIn, uint256 amtIn, uint256 amtOut, address to);
    event FeeBpsUpdated(uint16 oldBps, uint16 newBps);
    event TradingOpened(bool open);

    /**
     * @dev Constructor
     * @param _rtk RTN token address
     * @param _usdc USDC token address
     * @param _kycOracle KYC Oracle address
     * @param _feeBps Fee in basis points (0-100)
     * @param _admin Admin address
     */
    constructor(
        address _rtk,
        address _usdc,
        address _kycOracle,
        uint16 _feeBps,
        address _admin
    ) {
        require(_rtk != address(0), "INVALID_RTK");
        require(_usdc != address(0), "INVALID_USDC");
        require(_kycOracle != address(0), "INVALID_KYC_ORACLE");
        require(_admin != address(0), "INVALID_ADMIN");
        require(_feeBps <= 100, "FEE_TOO_HIGH");

        // Check decimals
        require(
            IERC20Decimals(_rtk).decimals() == 6 && IERC20Decimals(_usdc).decimals() == 6,
            "DECIMALS_6_REQUIRED"
        );

        rtk = _rtk;
        usdc = _usdc;
        kyc = IKYCOracle(_kycOracle);
        feeBps = _feeBps;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /**
     * @dev Modifier to check KYC status
     */
    modifier kycRequired(address account) {
        require(kyc.isWhitelisted(account), "KYC_REQUIRED");
        _;
    }

    /**
     * @dev Modifier to check deadline
     */
    modifier checkDeadline(uint256 deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    /**
     * @dev Modifier to check if trading is open
     */
    modifier tradingOpen() {
        require(isOpen, "CLOSED");
        _;
    }

    // ============ READ FUNCTIONS ============

    /**
     * @dev Get current reserves
     */
    function getReserves() public view returns (uint112 _reserveRTN, uint112 _reserveUSDC, uint32 _blockTimestampLast) {
        _reserveRTN = reserveRTN;
        _reserveUSDC = reserveUSDC;
        _blockTimestampLast = blockTimestampLast;
    }

    /**
     * @dev Get price of RTN in USDC (with 6 decimals precision)
     */
    function getPriceRTNinUSDC() external view returns (uint256) {
        if (reserveRTN == 0) return 0;
        return (uint256(reserveUSDC) * 1e6) / uint256(reserveRTN);
    }

    /**
     * @dev Get price of USDC in RTN (with 6 decimals precision)
     */
    function getPriceUSDCinRTN() external view returns (uint256) {
        if (reserveUSDC == 0) return 0;
        return (uint256(reserveRTN) * 1e6) / uint256(reserveUSDC);
    }

    /**
     * @dev Quote function for exact input
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        require(amountA > 0, "INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "INSUFFICIENT_LIQUIDITY");
        amountB = (amountA * reserveB) / reserveA;
    }

    /**
     * @dev Get amount out for exact input with fees
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public view returns (uint256 amountOut)
    {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * (10000 - feeBps) / 10000;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @dev Get amount in for exact output with fees
     */
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public view returns (uint256 amountIn)
    {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        require(amountOut < reserveOut, "INSUFFICIENT_LIQUIDITY");

        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = (reserveOut - amountOut) * (10000 - feeBps);
        amountIn = (numerator / denominator) + 1;
    }

    // ============ WRITE FUNCTIONS ============

    /**
     * @dev Add liquidity to the pool
     */
    function addLiquidity(
        uint256 amtRTN,
        uint256 amtUSDC,
        uint256 minShares,
        uint256 deadline
    )
        external
        nonReentrant
        whenNotPaused
        tradingOpen
        kycRequired(msg.sender)
        checkDeadline(deadline)
        returns (uint256 newShares)
    {
        require(amtRTN > 0 && amtUSDC > 0, "INSUFFICIENT_AMOUNT");

        // Transfer tokens first
        IERC20(rtk).safeTransferFrom(msg.sender, address(this), amtRTN);
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amtUSDC);

        uint256 _totalShares = totalShares;
        if (_totalShares == 0) {
            // First liquidity addition
            newShares = _sqrt(amtRTN * amtUSDC) - MIN_LIQUIDITY;
            require(newShares > 0, "INSUFFICIENT_LIQUIDITY_MINTED");

            // Lock minimum liquidity
            shares[address(0)] = MIN_LIQUIDITY;
            totalShares = newShares + MIN_LIQUIDITY;
        } else {
            // Subsequent additions
            uint256 _reserveRTN = uint256(reserveRTN);
            uint256 _reserveUSDC = uint256(reserveUSDC);

            uint256 sharesFromRTN = (amtRTN * _totalShares) / _reserveRTN;
            uint256 sharesFromUSDC = (amtUSDC * _totalShares) / _reserveUSDC;

            newShares = sharesFromRTN < sharesFromUSDC ? sharesFromRTN : sharesFromUSDC;
            require(newShares > 0, "INSUFFICIENT_LIQUIDITY_MINTED");

            totalShares = _totalShares + newShares;
        }

        require(newShares >= minShares, "SLIPPAGE");

        shares[msg.sender] += newShares;
        _syncReserves();

        emit MintShares(msg.sender, newShares, amtRTN, amtUSDC);
    }

    /**
     * @dev Remove liquidity from the pool
     */
    function removeLiquidity(
        uint256 sharesAmt,
        uint256 minRTN,
        uint256 minUSDC,
        uint256 deadline
    )
        external
        nonReentrant
        whenNotPaused
        tradingOpen
        kycRequired(msg.sender)
        checkDeadline(deadline)
        returns (uint256 outRTN, uint256 outUSDC)
    {
        require(sharesAmt > 0, "INSUFFICIENT_AMOUNT");
        require(shares[msg.sender] >= sharesAmt, "INSUFFICIENT_SHARES");

        uint256 _totalShares = totalShares;
        uint256 balanceRTN = IERC20(rtk).balanceOf(address(this));
        uint256 balanceUSDC = IERC20(usdc).balanceOf(address(this));

        outRTN = (sharesAmt * balanceRTN) / _totalShares;
        outUSDC = (sharesAmt * balanceUSDC) / _totalShares;

        require(outRTN >= minRTN && outUSDC >= minUSDC, "SLIPPAGE");

        shares[msg.sender] -= sharesAmt;
        totalShares = _totalShares - sharesAmt;

        IERC20(rtk).safeTransfer(msg.sender, outRTN);
        IERC20(usdc).safeTransfer(msg.sender, outUSDC);

        _syncReserves();

        emit BurnShares(msg.sender, sharesAmt, outRTN, outUSDC, msg.sender);
    }

    /**
     * @dev Swap exact RTN for USDC
     */
    function swapExactRTNForUSDC(
        uint256 amtIn,
        uint256 minOut,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        whenNotPaused
        tradingOpen
        kycRequired(msg.sender)
        kycRequired(to)
        checkDeadline(deadline)
        returns (uint256 outUSDC)
    {
        require(amtIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(to != address(0), "INVALID_TO");

        IERC20(rtk).safeTransferFrom(msg.sender, address(this), amtIn);

        uint256 _reserveRTN = uint256(reserveRTN);
        uint256 _reserveUSDC = uint256(reserveUSDC);

        outUSDC = getAmountOut(amtIn, _reserveRTN, _reserveUSDC);
        require(outUSDC >= minOut, "SLIPPAGE");

        IERC20(usdc).safeTransfer(to, outUSDC);
        _syncReserves();

        emit Swap(msg.sender, true, amtIn, outUSDC, to);
    }

    /**
     * @dev Swap exact USDC for RTN
     */
    function swapExactUSDCForRTN(
        uint256 amtIn,
        uint256 minOut,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        whenNotPaused
        tradingOpen
        kycRequired(msg.sender)
        kycRequired(to)
        checkDeadline(deadline)
        returns (uint256 outRTN)
    {
        require(amtIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(to != address(0), "INVALID_TO");

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amtIn);

        uint256 _reserveRTN = uint256(reserveRTN);
        uint256 _reserveUSDC = uint256(reserveUSDC);

        outRTN = getAmountOut(amtIn, _reserveUSDC, _reserveRTN);
        require(outRTN >= minOut, "SLIPPAGE");

        IERC20(rtk).safeTransfer(to, outRTN);
        _syncReserves();

        emit Swap(msg.sender, false, amtIn, outRTN, to);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Set fee in basis points (0-100)
     */
    function setFeeBps(uint16 newBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newBps <= 100, "FEE_TOO_HIGH");
        uint16 oldBps = feeBps;
        feeBps = newBps;
        emit FeeBpsUpdated(oldBps, newBps);
    }

    /**
     * @dev Open trading
     */
    function openTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        isOpen = true;
        emit TradingOpened(true);
    }

    /**
     * @dev Close trading
     */
    function closeTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        isOpen = false;
        emit TradingOpened(false);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Sync reserves to current token balances
     */
    function _syncReserves() private {
        uint256 balanceRTN = IERC20(rtk).balanceOf(address(this));
        uint256 balanceUSDC = IERC20(usdc).balanceOf(address(this));

        require(balanceRTN <= type(uint112).max && balanceUSDC <= type(uint112).max, "OVERFLOW");

        reserveRTN = uint112(balanceRTN);
        reserveUSDC = uint112(balanceUSDC);
        blockTimestampLast = uint32(block.timestamp);

        emit PoolSynced(reserveRTN, reserveUSDC);
    }

    /**
     * @dev Babylonian method for square root
     */
    function _sqrt(uint256 y) private pure returns (uint256 z) {
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
