// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IKYC Oracle Interface
 * @dev Interface for KYC verification
 */
interface IKYC {
    /**
     * @dev Check if an address is whitelisted
     * @param addr Address to check
     * @return bool True if address is whitelisted
     */
    function isWhitelisted(address addr) external view returns (bool);
}
