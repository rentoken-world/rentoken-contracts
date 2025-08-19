// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ISanctionOracle.sol";

/**
 * @title Sanction Oracle Contract
 * @dev Implementation of sanction verification
 */
contract SanctionOracle is ISanction, Ownable {
    // Mapping from address to sanction status
    mapping(address => bool) public sanctionedAddresses;

    // Events
    event AddressSanctioned(address indexed addr);
    event AddressUnsanctioned(address indexed addr);
    event BatchSanctionUpdated(address[] addresses, bool[] statuses);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add address to sanction list
     * @param addr Address to sanction
     */
    function addToSanctionList(address addr) external onlyOwner {
        require(addr != address(0), "SanctionOracle: Invalid address");
        require(!sanctionedAddresses[addr], "SanctionOracle: Already sanctioned");

        sanctionedAddresses[addr] = true;
        emit AddressSanctioned(addr);
    }

    /**
     * @dev Remove address from sanction list
     * @param addr Address to unsanction
     */
    function removeFromSanctionList(address addr) external onlyOwner {
        require(sanctionedAddresses[addr], "SanctionOracle: Not sanctioned");

        sanctionedAddresses[addr] = false;
        emit AddressUnsanctioned(addr);
    }

    /**
     * @dev Batch update sanction list
     * @param addresses Array of addresses
     * @param statuses Array of statuses (true for sanction, false for unsanction)
     */
    function batchUpdateSanctions(address[] calldata addresses, bool[] calldata statuses) external onlyOwner {
        require(addresses.length == statuses.length, "SanctionOracle: Array length mismatch");

        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "SanctionOracle: Invalid address");
            sanctionedAddresses[addresses[i]] = statuses[i];

            if (statuses[i]) {
                emit AddressSanctioned(addresses[i]);
            } else {
                emit AddressUnsanctioned(addresses[i]);
            }
        }

        emit BatchSanctionUpdated(addresses, statuses);
    }

    /**
     * @dev Check if address is sanctioned
     * @param addr Address to check
     * @return True if address is sanctioned
     */
    function isSanctioned(address addr) external view override returns (bool) {
        return sanctionedAddresses[addr];
    }

    /**
     * @dev Check multiple addresses at once
     * @param addresses Array of addresses to check
     * @return Array of sanction statuses
     */
    function batchCheckSanctions(address[] calldata addresses) external view returns (bool[] memory) {
        bool[] memory results = new bool[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            results[i] = sanctionedAddresses[addresses[i]];
        }

        return results;
    }

    /**
     * @dev Emergency function to clear all sanctions
     */
    function clearAllSanctions() external onlyOwner {
        // This is a destructive operation, use with caution
        // In production, consider adding a timelock or multi-sig requirement
    }
}
