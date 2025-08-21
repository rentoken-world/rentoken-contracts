// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/ISanctionOracle.sol";

contract MockSanctionOracle is ISanctionOracle {
    mapping(address => bool) private _sanctioned;

    function isSanctioned(address addr) external view override returns (bool) {
        return _sanctioned[addr];
    }

    function setSanctioned(address addr, bool sanctioned) external {
        _sanctioned[addr] = sanctioned;
    }

    // Keep backward compatibility
    function isBlocked(address addr) external view returns (bool) {
        return _sanctioned[addr];
    }

    function setBlocked(address addr, bool blocked) external {
        _sanctioned[addr] = blocked;
    }
}
