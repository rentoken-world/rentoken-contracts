// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISanction Oracle Interface
 * @dev Interface for sanction verification
 */
interface ISanction {
    /**
     * @dev Check if an address is sanctioned
     * @param addr Address to check
     * @return bool True if address is sanctioned
     */
    function isSanctioned(address addr) external view returns (bool);
}
