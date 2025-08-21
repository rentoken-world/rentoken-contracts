// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/RentToken.sol";
import "../src/PropertyOracle.sol";
import "../src/KYCOracle.sol";
import "../src/mocks/MockUSDCWithPermit.sol";
import "../src/mocks/MockSanctionOracle.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract RentTokenPermitTest is Test {
	RentToken public rentToken;
	PropertyOracle public propertyOracle;
	KYCOracle public kycOracle;
	MockSanctionOracle public sanctionOracle;
	MockUSDCWithPermit public usdc;

	address public admin = makeAddr("admin");
	address public user = makeAddr("user");
	address public landlord = makeAddr("landlord");
	address public factory = makeAddr("factory");

	uint256 public constant PROPERTY_ID = 9;
	uint256 public constant MIN_RAISING = 10_000e6;
	uint256 public constant MAX_RAISING = 100_000e6;
	uint64 public accrualStart;
	uint64 public accrualEnd;

	address public rentTokenImpl;

	function setUp() public {
		vm.prank(admin);
		usdc = new MockUSDCWithPermit();

		vm.prank(admin);
		propertyOracle = new PropertyOracle();

		vm.prank(admin);
		kycOracle = new KYCOracle();

		vm.prank(admin);
		sanctionOracle = new MockSanctionOracle();

		accrualStart = uint64(block.timestamp + 1 days);
		accrualEnd = uint64(block.timestamp + 365 days);

		PropertyOracle.PropertyData memory data = PropertyOracle.PropertyData({
			propertyId: PROPERTY_ID,
			payoutToken: address(usdc),
			valuation: 1_000_000e6,
			minRaising: MIN_RAISING,
			maxRaising: MAX_RAISING,
			accrualStart: accrualStart,
			accrualEnd: accrualEnd,
			landlord: landlord,
			docHash: keccak256("docs"),
			offchainURL: "https://example.com"
		});

		vm.prank(admin);
		propertyOracle.addOrUpdateProperty(PROPERTY_ID, data);

		// Deploy implementation and clone
		rentTokenImpl = address(new RentToken());
		address proxy = Clones.clone(rentTokenImpl);

		RentToken(proxy).initialize(
			"RenToken Permit Test",
			"RTNP",
			PROPERTY_ID,
			address(usdc),
			MIN_RAISING,
			MAX_RAISING,
			accrualStart,
			accrualEnd,
			landlord,
			factory,
			address(propertyOracle),
			address(kycOracle),
			address(sanctionOracle)
		);

		rentToken = RentToken(proxy);

		vm.prank(admin);
		kycOracle.addToWhitelist(user);

		vm.prank(admin);
		usdc.mint(user, 50_000e6);
	}

	function test_permitDeposit_basic() public {
		uint256 amount = 12_345e6;
		uint256 privateKey = 0xA11CE; // test key to sign permit
		address owner = vm.addr(privateKey);

		// Fund owner and whitelist
		vm.prank(admin);
		usdc.mint(owner, amount);
		vm.prank(admin);
		kycOracle.addToWhitelist(owner);

		// EIP-2612 permit signature
		uint256 nonce = usdc.nonces(owner);
		uint256 deadline = block.timestamp + 1 days;
		bytes32 domainSeparator = usdc.DOMAIN_SEPARATOR();
		bytes32 structHash = keccak256(
			abi.encode(
				keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
				owner,
				address(rentToken),
				amount,
				nonce,
				deadline
			)
		);
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

		// Call permitDeposit as owner
		vm.prank(owner);
		rentToken.permitDeposit(amount, deadline, v, r, s);

		assertEq(rentToken.balanceOf(owner), amount);
		assertEq(rentToken.totalFundRaised(), amount);
		assertEq(usdc.balanceOf(address(rentToken)), amount);
	}

	function test_permitDeposit_expiredDeadline_reverts() public {
		uint256 amount = 1_000e6;
		uint256 privateKey = 0xB0B; // test key
		address owner = vm.addr(privateKey);
		vm.prank(admin);
		usdc.mint(owner, amount);
		vm.prank(admin);
		kycOracle.addToWhitelist(owner);

		uint256 nonce = usdc.nonces(owner);
		uint256 deadline = block.timestamp - 1; // expired
		bytes32 domainSeparator = usdc.DOMAIN_SEPARATOR();
		bytes32 structHash = keccak256(
			abi.encode(
				keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
				owner,
				address(rentToken),
				amount,
				nonce,
				deadline
			)
		);
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

		vm.startPrank(owner);
		vm.expectRevert();
		rentToken.permitDeposit(amount, deadline, v, r, s);
		vm.stopPrank();
	}

	function test_permitDeposit_kycReverts() public {
		uint256 amount = 500e6;
		uint256 privateKey = 0xD00D;
		address owner = vm.addr(privateKey);
		vm.prank(admin);
		usdc.mint(owner, amount);
		// not whitelisted on purpose

		uint256 nonce = usdc.nonces(owner);
		uint256 deadline = block.timestamp + 1 days;
		bytes32 domainSeparator = usdc.DOMAIN_SEPARATOR();
		bytes32 structHash = keccak256(
			abi.encode(
				keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
				owner,
				address(rentToken),
				amount,
				nonce,
				deadline
			)
		);
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

		vm.startPrank(owner);
		vm.expectRevert(bytes("RentToken: User not whitelisted"));
		rentToken.permitDeposit(amount, deadline, v, r, s);
		vm.stopPrank();
	}
}
