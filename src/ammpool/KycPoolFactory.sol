// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./KycPool.sol";



/**
 * @title KycPoolFactory Contract
 * @dev Factory for creating unique KYC pools per propertyId
 */
contract KycPoolFactory is AccessControl {

    // Oracle
    IKYCOracle public kyc;

    // Mapping from propertyId to pool address
    mapping(uint256 => address) public poolOf;

    // Events
    event PoolCreated(
        uint256 indexed propertyId,
        address pool,
        address rtk,
        address usdc,
        uint16 feeBps
    );

    /**
     * @dev Constructor
     * @param _kycOracle KYC Oracle address
     * @param _admin Admin address
     */
    constructor(address _kycOracle, address _admin) {
        require(_kycOracle != address(0), "INVALID_KYC_ORACLE");
        require(_admin != address(0), "INVALID_ADMIN");

        kyc = IKYCOracle(_kycOracle);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @dev Create a new pool for a propertyId
     * @param propertyId The property ID
     * @param rtk RTN token address
     * @param usdc USDC token address
     * @param feeBps Fee in basis points (0-100)
     * @return pool The created pool address
     */
    function createPool(
        uint256 propertyId,
        address rtk,
        address usdc,
        uint16 feeBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address pool) {
        require(poolOf[propertyId] == address(0), "POOL_EXISTS");
        require(rtk != address(0), "INVALID_RTK");
        require(usdc != address(0), "INVALID_USDC");

        // Deploy new KycPool
        pool = address(new KycPool(
            rtk,
            usdc,
            address(kyc),
            feeBps,
            msg.sender // admin of the pool (should be the factory admin)
        ));

        // Record mapping
        poolOf[propertyId] = pool;

        emit PoolCreated(propertyId, pool, rtk, usdc, feeBps);
    }

    /**
     * @dev Open trading for a specific pool
     * @param propertyId The property ID
     */
    function openTrading(uint256 propertyId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address pool = poolOf[propertyId];
        require(pool != address(0), "POOL_NOT_EXISTS");

        KycPool(pool).openTrading();
    }

    /**
     * @dev Close trading for a specific pool
     * @param propertyId The property ID
     */
    function closeTrading(uint256 propertyId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address pool = poolOf[propertyId];
        require(pool != address(0), "POOL_NOT_EXISTS");

        KycPool(pool).closeTrading();
    }

    /**
     * @dev Get pool address for a propertyId
     * @param propertyId The property ID
     * @return The pool address (address(0) if not exists)
     */
    function getPool(uint256 propertyId) external view returns (address) {
        return poolOf[propertyId];
    }
}
