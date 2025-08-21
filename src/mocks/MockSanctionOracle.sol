// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/ISanctionOracle.sol";

contract MockSanctionOracle is ISanctionOracle {
    mapping(address => bool) private _blocked;

    function isSanctioned(address addr) external view returns (bool) {
        return _blocked[addr];
    }

    function setBlocked(address addr, bool blocked) external {
        _blocked[addr] = blocked;
    }
}
