// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Property Oracle Contract
 * @dev Oracle contract for real estate property information
 */
contract PropertyOracle is Ownable, Pausable {
    struct PropertyData {
        uint256 propertyId; // 资产ID
        address payoutToken; // 分红/募集币种(如 USDC)
        uint256 valuation; // 估值(未来现金流折现)
        uint256 minRaising; // 最小募集额(USDC)
        uint256 maxRaising; // 最大募集额(USDC)
        uint64 accrualStart; // 起息(Unix time)
        uint64 accrualEnd; // 止息(Unix time)
        uint16 feeBps; // 平台费,基点（本版净额已在链下扣除，可设 0 或忽略）
        address landlord; // 房东/收益权所有者
        bytes32 docHash; // 线下材料的内容哈希(如 IPFS 文件的 keccak256)
        string city; // 城市(可选,字符串要谨慎,Gas 贵)
        string offchainURL; // 资料URL(可选)
    }

    // Mapping from propertyId to PropertyData
    mapping(uint256 => PropertyData) public properties;

    // Mapping from propertyId to version number
    mapping(uint256 => uint64) public propertyVersions;

    // Events
    event PropertyAdded(uint256 indexed propertyId, address indexed landlord, uint256 minRaising, uint256 maxRaising);
    event PropertyUpdated(uint256 indexed propertyId, uint64 version);
    event PropertyRemoved(uint256 indexed propertyId);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add or update a property
     * @param propertyId The property ID
     * @param data The property data
     */
    function addOrUpdateProperty(uint256 propertyId, PropertyData calldata data) external onlyOwner {
        require(data.propertyId == propertyId, "PropertyOracle: ID mismatch");
        require(data.payoutToken != address(0), "PropertyOracle: Invalid payout token");
        require(data.landlord != address(0), "PropertyOracle: Invalid landlord");
        require(data.accrualStart < data.accrualEnd, "PropertyOracle: Invalid time range");
        require(data.minRaising <= data.maxRaising, "PropertyOracle: Invalid raising range");

        properties[propertyId] = data;
        propertyVersions[propertyId]++;

        emit PropertyUpdated(propertyId, propertyVersions[propertyId]);

        if (propertyVersions[propertyId] == 1) {
            emit PropertyAdded(propertyId, data.landlord, data.minRaising, data.maxRaising);
        }
    }

    /**
     * @dev Remove a property
     * @param propertyId The property ID to remove
     */
    function removeProperty(uint256 propertyId) external onlyOwner {
        require(properties[propertyId].propertyId != 0, "PropertyOracle: Property not found");

        delete properties[propertyId];
        emit PropertyRemoved(propertyId);
    }

    /**
     * @dev Get property data
     * @param propertyId The property ID
     * @return data The property data
     * @return version The current version
     */
    function getProperty(uint256 propertyId) external view returns (PropertyData memory data, uint64 version) {
        data = properties[propertyId];
        require(data.propertyId != 0, "PropertyOracle: Property not found");
        version = propertyVersions[propertyId];
    }

    /**
     * @dev Get property data in packed format
     * @param propertyId The property ID
     * @return packed The packed property data
     * @return version The current version
     */
    function getPropertyPacked(uint256 propertyId) external view returns (bytes memory packed, uint64 version) {
        PropertyData memory data = properties[propertyId];
        require(data.propertyId != 0, "PropertyOracle: Property not found");

        packed = abi.encode(data);
        version = propertyVersions[propertyId];
    }

    /**
     * @dev Get property version
     * @param propertyId The property ID
     * @return The current version
     */
    function versionOf(uint256 propertyId) external view returns (uint64) {
        return propertyVersions[propertyId];
    }

    /**
     * @dev Check if property exists
     * @param propertyId The property ID
     * @return True if property exists
     */
    function propertyExists(uint256 propertyId) external view returns (bool) {
        return properties[propertyId].propertyId != 0;
    }

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
}
