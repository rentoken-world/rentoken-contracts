// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IKYCOracle.sol";
import "./interfaces/ISanctionOracle.sol";

/**
 * @title RentToken Contract
 * @dev ERC20 token representing future rental income from real estate
 */
contract RentToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // Contract phases
    enum Phase {
        Fundraising, // 认购阶段
        AccrualStarted, // 发售成功运行中
        RisingFailed, // 筹款失败
        AccrualFinished, // 合约到期
        Terminated // 合约终止

    }

    // Property information
    uint256 public propertyId;
    address public payoutToken;
    uint256 public minRaising;
    uint256 public maxRaising;
    uint64 public accrualStart;
    uint64 public accrualEnd;
    address public landlordWalletAddress;
    address public seriesFactory;

    // Oracle contracts
    address public propertyOracle;
    address public kycOracle;
    address public sanctionOracle;

    // Financial tracking
    uint256 public totalFundRaised;
    uint256 public totalProfitReceived;
    uint256 public accumulatedRewardPerToken;

    // User tracking
    mapping(address => uint256) public debt;
    mapping(address => uint256) public claimable;

    // Events
    event ProfitReceived(uint256 amount, uint256 newAccumulatedReward);
    event ProfitClaimed(address indexed user, uint256 amount);
    event ContributionReceived(address indexed user, uint256 amount, uint256 tokensMinted);
    event RefundProcessed(address indexed user, uint256 amount);
    event PhaseChanged(Phase oldPhase, Phase newPhase);

    // Modifiers
    modifier onlySeriesFactory() {
        require(msg.sender == seriesFactory, "RentToken: Only SeriesFactory can call");
        _;
    }

    modifier onlyInPhase(Phase phase) {
        require(getPhase() == phase, "RentToken: Wrong phase");
        _;
    }

    modifier kycAndSanctionCheck(address from, address to) {
        if (from != address(0) && to != address(0)) {
            require(IKYC(kycOracle).isWhitelisted(from), "RentToken: Sender not KYC verified");
            require(IKYC(kycOracle).isWhitelisted(to), "RentToken: Recipient not KYC verified");
            require(!ISanctionOracle(sanctionOracle).isSanctioned(from), "RentToken: Sender is sanctioned");
            require(!ISanctionOracle(sanctionOracle).isSanctioned(to), "RentToken: Recipient is sanctioned");
        }
        _;
    }

    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow-constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract
     */
    function initialize(
        string memory name,
        string memory symbol,
        uint256 _propertyId,
        address _payoutToken,
        uint256 _minRaising,
        uint256 _maxRaising,
        uint64 _accrualStart,
        uint64 _accrualEnd,
        address _landlordWalletAddress,
        address _seriesFactory,
        address _propertyOracle,
        address _kycOracle,
        address _sanctionOracle
    ) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();

        propertyId = _propertyId;
        payoutToken = _payoutToken;
        minRaising = _minRaising;
        maxRaising = _maxRaising;
        accrualStart = _accrualStart;
        accrualEnd = _accrualEnd;
        landlordWalletAddress = _landlordWalletAddress;
        seriesFactory = _seriesFactory;
        propertyOracle = _propertyOracle;
        kycOracle = _kycOracle;
        sanctionOracle = _sanctionOracle;

        // Note: ERC20 tokens use 18 decimals by default in OpenZeppelin v5
    }

    /**
     * @dev Get current contract phase
     */
    function getPhase() public view returns (Phase) {
        if (block.timestamp < accrualStart) {
            return Phase.Fundraising;
        } else if (block.timestamp >= accrualStart && block.timestamp < accrualEnd) {
            if (totalFundRaised >= minRaising) {
                return Phase.AccrualStarted;
            } else {
                return Phase.RisingFailed;
            }
        } else if (block.timestamp >= accrualEnd) {
            if (totalFundRaised >= minRaising) {
                return Phase.AccrualFinished;
            } else {
                return Phase.RisingFailed;
            }
        }

        // Check if terminated (180 days after end)
        if (block.timestamp >= accrualEnd + 180 days) {
            return Phase.Terminated;
        }

        return Phase.AccrualFinished;
    }

    /**
     * @dev Contribute USDC to get RTN tokens (only in fundraising phase)
     */
    function contribute(uint256 amount) external onlyInPhase(Phase.Fundraising) updateReward(msg.sender) {
        require(amount > 0, "RentToken: Amount must be positive");
        require(totalFundRaised + amount <= maxRaising, "RentToken: Exceeds max raising");

        // Transfer USDC from user
        IERC20(payoutToken).safeTransferFrom(msg.sender, address(this), amount);

        // Mint RTN tokens 1:1
        _mint(msg.sender, amount);
        totalFundRaised += amount;

        emit ContributionReceived(msg.sender, amount, amount);
    }

    /**
     * @dev Receive profit from SeriesFactory
     */
    function receiveProfit(uint256 amount) external onlySeriesFactory onlyInPhase(Phase.AccrualStarted) {
        require(amount > 0, "RentToken: Amount must be positive");

        // Update accumulated reward per token
        if (totalSupply() > 0) {
            accumulatedRewardPerToken += (amount * 1e18) / totalSupply();
        }

        totalProfitReceived += amount;

        emit ProfitReceived(amount, accumulatedRewardPerToken);
    }

    /**
     * @dev Claim accumulated profits
     */
    function claim() external updateReward(msg.sender) {
        uint256 amount = claimable[msg.sender];
        require(amount > 0, "RentToken: No profits to claim");

        claimable[msg.sender] = 0;

        // Transfer USDC to user
        IERC20(payoutToken).safeTransfer(msg.sender, amount);

        emit ProfitClaimed(msg.sender, amount);
    }

    /**
     * @dev Refund USDC in case of fundraising failure
     */
    function refund() external onlyInPhase(Phase.RisingFailed) updateReward(msg.sender) {
        uint256 amount = balanceOf(msg.sender);
        require(amount > 0, "RentToken: No tokens to refund");

        // Burn tokens
        _burn(msg.sender, amount);

        // Transfer USDC back to user
        IERC20(payoutToken).safeTransfer(msg.sender, amount);

        emit RefundProcessed(msg.sender, amount);
    }

    /**
     * @dev Update reward for an account
     */
    function _updateReward(address account) internal {
        uint256 reward = (balanceOf(account) * accumulatedRewardPerToken / 1e18) - debt[account];
        if (reward > 0) {
            claimable[account] += reward;
        }
        debt[account] = balanceOf(account) * accumulatedRewardPerToken / 1e18;
    }

    /**
     * @dev Override _update to include KYC/sanction checks and reward updates
     */
    function _update(address from, address to, uint256 amount)
        internal
        virtual
        override
        kycAndSanctionCheck(from, to)
        updateReward(from)
        updateReward(to)
    {
        if (from != address(0)) {
            require(getPhase() != Phase.Fundraising, "RentToken: Transfers not allowed in fundraising");
        }
        require(getPhase() != Phase.Terminated, "RentToken: Contract terminated");

        super._update(from, to, amount);
    }

    /**
     * @dev Override approve to include KYC/sanction checks
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        override
        kycAndSanctionCheck(msg.sender, spender)
        returns (bool)
    {
        require(getPhase() != Phase.Fundraising, "RentToken: Approvals not allowed in fundraising");
        require(getPhase() != Phase.Terminated, "RentToken: Contract terminated");

        return super.approve(spender, amount);
    }

    /**
     * @dev Override transferFrom to include KYC/sanction checks and reward updates
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        kycAndSanctionCheck(from, to)
        updateReward(from)
        updateReward(to)
        returns (bool)
    {
        require(getPhase() != Phase.Fundraising, "RentToken: Transfers not allowed in fundraising");
        require(getPhase() != Phase.Terminated, "RentToken: Contract terminated");

        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Admin function to withdraw remaining USDC after termination
     */
    function withdrawRemainingFunds() external onlyOwner {
        require(getPhase() == Phase.Terminated, "RentToken: Not terminated yet");

        uint256 balance = IERC20(payoutToken).balanceOf(address(this));
        require(balance > 0, "RentToken: No funds to withdraw");

        IERC20(payoutToken).safeTransfer(owner(), balance);
    }

    /**
     * @dev Get claimable amount for an account
     */
    function getClaimableAmount(address account) external view returns (uint256) {
        uint256 reward = (balanceOf(account) * accumulatedRewardPerToken / 1e18) - debt[account];
        return claimable[account] + reward;
    }

    /**
     * @dev Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    function setKYCOracle(address _kycOracle) external onlyOwner {
        kycOracle = _kycOracle;
    }

    function setSanctionOracle(address _sanctionOracle) external onlyOwner {
        sanctionOracle = _sanctionOracle;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
