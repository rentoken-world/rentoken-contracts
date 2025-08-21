// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDCWithPermit is ERC20, ERC20Permit {
	constructor() ERC20("Mock USDC Permit", "mUSDCp") ERC20Permit("Mock USDC Permit") {}

	function decimals() public pure override returns (uint8) {
		return 6;
	}

	function mint(address to, uint256 amount) external {
		_mint(to, amount);
	}
}
