// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IKYCOracle.sol";

/**
 * @title KYC Oracle Contract
 * @dev Implementation of KYC verification
 */
contract KYCOracle is IKYC, Ownable {
    // Mapping from address to KYC status
    mapping(address => bool) public kycWhitelist;

    // Events
    event AddressWhitelisted(address indexed addr);
    event AddressRemoved(address indexed addr);
    event BatchWhitelistUpdated(address[] addresses, bool[] statuses);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add address to KYC whitelist
     * @param addr Address to whitelist
     */
    function addToWhitelist(address addr) external onlyOwner {
        require(addr != address(0), "KYCOracle: Invalid address");
        require(!kycWhitelist[addr], "KYCOracle: Already whitelisted");

        kycWhitelist[addr] = true;
        emit AddressWhitelisted(addr);
    }

    /**
     * @dev Remove address from KYC whitelist
     * @param addr Address to remove
     */
    function removeFromWhitelist(address addr) external onlyOwner {
        require(kycWhitelist[addr], "KYCOracle: Not whitelisted");

        kycWhitelist[addr] = false;
        emit AddressRemoved(addr);
    }

    /**
     * @dev Batch update KYC whitelist
     * @param addresses Array of addresses
     * @param statuses Array of statuses (true for whitelist, false for remove)
     */
    function batchUpdateWhitelist(address[] calldata addresses, bool[] calldata statuses) external onlyOwner {
        require(addresses.length == statuses.length, "KYCOracle: Array length mismatch");

        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "KYCOracle: Invalid address");
            kycWhitelist[addresses[i]] = statuses[i];

            if (statuses[i]) {
                emit AddressWhitelisted(addresses[i]);
            } else {
                emit AddressRemoved(addresses[i]);
            }
        }

        emit BatchWhitelistUpdated(addresses, statuses);
    }

    /**
     * @dev Check if address is whitelisted
     * @param addr Address to check
     * @return True if address is whitelisted
     */
    function isWhitelisted(address addr) external view override returns (bool) {
        return kycWhitelist[addr];
    }

    /**
     * @dev Check multiple addresses at once
     * @param addresses Array of addresses to check
     * @return Array of whitelist statuses
     */
    function batchCheckWhitelist(address[] calldata addresses) external view returns (bool[] memory) {
        bool[] memory results = new bool[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            results[i] = kycWhitelist[addresses[i]];
        }

        return results;
    }
}
