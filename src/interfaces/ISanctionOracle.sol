// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ISanction Oracle Interface
 * @dev Interface for sanction verification
 */
interface ISanctionOracle {
    function isSanctioned(address addr) external view returns (bool);
}
