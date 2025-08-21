// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./PropertyOracle.sol";
import "./RentToken.sol";

/**
 * @title Series Factory Contract
 * @dev Main platform contract for managing RTN token series
 */
contract SeriesFactory is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Role definitions
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Contract addresses
    address public propertyOracle;
    address public rentTokenImplementation;

    // Mappings
    mapping(uint256 => address) public propertyIdToSeries;
    mapping(address => bool) public isSeriesContract;

    // Events
    event SeriesCreated(uint256 indexed propertyId, address indexed seriesAddress, string name, string symbol);
    event ProfitForwarded(uint256 indexed propertyId, address indexed series, uint256 amount, address operator);
    event PropertyOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event RentTokenImplementationUpdated(address indexed oldImpl, address indexed newImpl);

    // Modifiers
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "SeriesFactory: Only operator can call");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SeriesFactory: Only admin can call");
        _;
    }

    constructor(address _propertyOracle) {
        propertyOracle = _propertyOracle;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Create a new RTN series for a property
     * @param propertyId The property ID from PropertyOracle
     * @param name Token name (e.g., "RenToken Amsterdam 001")
     * @param symbol Token symbol (e.g., "RTAMS1")
     */
    function createSeries(uint256 propertyId, string memory name, string memory symbol)
        external
        onlyAdmin
        returns (address)
    {
        require(propertyIdToSeries[propertyId] == address(0), "SeriesFactory: Series already exists");
        require(rentTokenImplementation != address(0), "SeriesFactory: Implementation not set");

        // Get property data from oracle
        (PropertyOracle.PropertyData memory propertyData,) = PropertyOracle(propertyOracle).getProperty(propertyId);
        require(propertyData.propertyId != 0, "SeriesFactory: Property not found");

        // Clone the implementation
        address seriesAddress = Clones.clone(rentTokenImplementation);

        // Initialize the series
        RentToken(seriesAddress).initialize(
            name,
            symbol,
            propertyId,
            propertyData.payoutToken,
            propertyData.minRaising,
            propertyData.maxRaising,
            propertyData.accrualStart,
            propertyData.accrualEnd,
            propertyData.landlord,
            address(this),
            propertyOracle,
            address(0), // KYC Oracle - to be set later
            address(0) // Sanction Oracle - to be set later
        );

        // Record the series
        propertyIdToSeries[propertyId] = seriesAddress;
        isSeriesContract[seriesAddress] = true;

        emit SeriesCreated(propertyId, seriesAddress, name, symbol);

        return seriesAddress;
    }

    /**
     * @dev Forward profit to a specific series
     * @param propertyId The property ID
     * @param amount The profit amount in USDC
     */
    function receiveProfit(uint256 propertyId, uint256 amount) external onlyOperator nonReentrant whenNotPaused {
        require(amount > 0, "SeriesFactory: Amount must be positive");

        address seriesAddress = propertyIdToSeries[propertyId];
        require(seriesAddress != address(0), "SeriesFactory: Series not found");

        // Transfer USDC from operator to series
        IERC20(getPayoutToken(propertyId)).safeTransferFrom(msg.sender, seriesAddress, amount);

        // Call series contract to receive profit
        RentToken(seriesAddress).receiveProfit(amount);

        emit ProfitForwarded(propertyId, seriesAddress, amount, msg.sender);
    }

    /**
     * @dev Get payout token for a property
     * @param propertyId The property ID
     * @return The payout token address
     */
    function getPayoutToken(uint256 propertyId) public view returns (address) {
        (PropertyOracle.PropertyData memory propertyData,) = PropertyOracle(propertyOracle).getProperty(propertyId);
        return propertyData.payoutToken;
    }

    /**
     * @dev Get series address for a property
     * @param propertyId The property ID
     * @return The series contract address
     */
    function getSeriesAddress(uint256 propertyId) external view returns (address) {
        return propertyIdToSeries[propertyId];
    }

    /**
     * @dev Check if a series exists for a property
     * @param propertyId The property ID
     * @return True if series exists
     */
    function seriesExists(uint256 propertyId) external view returns (bool) {
        return propertyIdToSeries[propertyId] != address(0);
    }

    /**
     * @dev Update property oracle address
     * @param newOracle The new oracle address
     */
    function updatePropertyOracle(address newOracle) external onlyAdmin {
        require(newOracle != address(0), "SeriesFactory: Invalid oracle address");
        address oldOracle = propertyOracle;
        propertyOracle = newOracle;
        emit PropertyOracleUpdated(oldOracle, newOracle);
    }

    /**
     * @dev Update rent token implementation
     * @param newImplementation The new implementation address
     */
    function updateRentTokenImplementation(address newImplementation) external onlyAdmin {
        require(newImplementation != address(0), "SeriesFactory: Invalid implementation");
        address oldImpl = rentTokenImplementation;
        rentTokenImplementation = newImplementation;
        emit RentTokenImplementationUpdated(oldImpl, newImplementation);
    }

    /**
     * @dev Set KYC and Sanction oracles for a series
     * @param propertyId The property ID
     * @param kycOracle The KYC oracle address
     * @param sanctionOracle The sanction oracle address
     */
    function setOraclesForSeries(uint256 propertyId, address kycOracle, address sanctionOracle) external onlyAdmin {
        address seriesAddress = propertyIdToSeries[propertyId];
        require(seriesAddress != address(0), "SeriesFactory: Series not found");

        RentToken(seriesAddress).setKYCOracle(kycOracle);
        RentToken(seriesAddress).setSanctionOracle(sanctionOracle);
    }

    /**
     * @dev Grant operator role
     * @param operator The operator address
     */
    function grantOperatorRole(address operator) external onlyAdmin {
        grantRole(OPERATOR_ROLE, operator);
    }

    /**
     * @dev Revoke operator role
     * @param operator The operator address
     */
    function revokeOperatorRole(address operator) external onlyAdmin {
        revokeRole(OPERATOR_ROLE, operator);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyAdmin {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyAdmin {
        _unpause();
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token The token address
     * @param to The recipient address
     * @param amount The amount to recover
     */
    function emergencyRecoverToken(address token, address to, uint256 amount) external onlyAdmin {
        require(to != address(0), "SeriesFactory: Invalid recipient");
        IERC20(token).safeTransfer(to, amount);
    }
}
