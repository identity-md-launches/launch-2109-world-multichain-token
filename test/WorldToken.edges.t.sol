// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldToken} from "../src/WorldToken.sol";

/// @notice Boundary cases and properties complementing WorldTokenTest. Failed calls must
///         preserve both balances and allowances, including work done before a late revert.
/// forge-config: default.fuzz.runs = 1000
contract WorldTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    WorldToken internal token;
    address internal deployer = makeAddr("edge-deployer");
    address internal alice = makeAddr("edge-alice");
    address internal bob = makeAddr("edge-bob");
    address internal carol = makeAddr("edge-carol");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new WorldToken();
    }

    function test_oneMinorUnitIsTransferableWithoutRounding() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 1);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsTransfer() public {
        bytes32 beforeState = _state(alice, bob, carol);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(_state(alice, bob, carol), beforeState);
    }

    function test_zeroTransferFromNeedsNeitherBalanceNorAllowance() public {
        bytes32 beforeState = _state(alice, carol, bob);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, carol, 0);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 0));
        assertEq(_state(alice, carol, bob), beforeState);
    }

    function test_zeroTransferToZeroStillReverts() public {
        bytes32 beforeState = _state(deployer, address(0), bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 0);
        assertEq(_state(deployer, address(0), bob), beforeState);
    }

    function test_zeroTransferFromToZeroStillReverts() public {
        bytes32 beforeState = _state(deployer, address(0), bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(deployer, address(0), 0);
        assertEq(_state(deployer, address(0), bob), beforeState);
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        bytes32 beforeState = _state(deployer, alice, address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(_state(deployer, alice, address(0)), beforeState);
    }

    function test_maximumTransferRevertsAndPreservesState() public {
        bytes32 beforeState = _state(deployer, alice, bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        assertEq(_state(deployer, alice, bob), beforeState);
    }

    function test_selfTransferAboveBalanceStillReverts() public {
        bytes32 beforeState = _state(deployer, deployer, bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY + 1);
        assertEq(_state(deployer, deployer, bob), beforeState);
    }

    function test_ownerUsingTransferFromMustApproveItself() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);

        _approve(deployer, deployer, 1);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_spenderCanBeTheRecipient() public {
        _approve(deployer, bob, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, bob, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, bob, 1));
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.allowance(deployer, bob), 0);
    }

    function test_maximumApprovalDoesNotRequireOrCreateBalance() public {
        _approve(alice, bob, type(uint256).max);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        _approve(deployer, bob, type(uint256).max - 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, bob), type(uint256).max - 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_infiniteAllowanceSurvivesRepeatedSpendingButCannotExceedBalance() public {
        _approve(deployer, bob, type(uint256).max);
        bytes32 beforeState = _state(deployer, alice, bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(bob);
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(_state(deployer, alice, bob), beforeState);

        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 1));
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY - 1));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.allowance(deployer, bob), type(uint256).max);

        beforeState = _state(deployer, alice, bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(_state(deployer, alice, bob), beforeState);
    }

    function test_infiniteAllowanceCanBeRevokedAndReplacedWithFiniteAllowance() public {
        _approve(deployer, bob, type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, bob, 0);
        _approve(deployer, bob, 0);
        assertEq(token.allowance(deployer, bob), 0);

        bytes32 beforeState = _state(deployer, alice, bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(_state(deployer, alice, bob), beforeState);

        _approve(deployer, bob, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function testFuzz_failedTransferFromPreservesAllowance(uint256 held, uint256 excess, bool infinite) public {
        held = bound(held, 0, SUPPLY);
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, held));
        _approve(alice, bob, infinite ? type(uint256).max : amount);

        bytes32 beforeState = _state(alice, carol, bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(bob);
        token.transferFrom(alice, carol, amount);
        assertEq(_state(alice, carol, bob), beforeState, "failed transfer consumed allowance or changed balances");
    }

    function testFuzz_zeroRecipientFailurePreservesAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(deployer, bob, infinite ? type(uint256).max : amount);
        bytes32 beforeState = _state(deployer, address(0), bob);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(deployer, address(0), amount);
        assertEq(_state(deployer, address(0), bob), beforeState, "invalid recipient consumed allowance");
    }

    function testFuzz_exhaustedAllowanceCannotBeReplayed(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        _approve(deployer, bob, amount);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);

        bytes32 beforeState = _state(deployer, alice, bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(_state(deployer, alice, bob), beforeState);
    }

    function testFuzz_approvalOnlyChangesTheSelectedOwnerSpenderPair(uint256 initial, uint256 replacement) public {
        _approve(deployer, bob, initial);
        _approve(deployer, carol, 17);
        _approve(alice, bob, 29);
        _approve(bob, deployer, 31);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, bob, replacement);
        _approve(deployer, bob, replacement);
        // Repeating an approval replaces the limit; it never accumulates it.
        _approve(deployer, bob, replacement);
        assertEq(token.allowance(deployer, bob), replacement);
        assertEq(token.allowance(deployer, carol), 17);
        assertEq(token.allowance(alice, bob), 29);
        assertEq(token.allowance(bob, deployer), 31);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferSpendsFiniteAllowance(uint256 amount, uint256 remainder) public {
        amount = bound(amount, 0, SUPPLY);
        remainder = bound(remainder, 0, type(uint256).max - 1 - amount);
        _approve(deployer, bob, amount + remainder);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, amount);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, deployer, amount));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(deployer, bob), remainder);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev A metamorphic property: splitting a delegated payment cannot change its final
    ///      balance or allowance effects. Both sides exercise the real token implementation.
    function testFuzz_splitDelegatedTransfersEqualSingleTransfer(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        vm.prank(deployer);
        WorldToken single = new WorldToken();
        vm.prank(deployer);
        assertTrue(single.approve(bob, amount));
        _approve(deployer, bob, amount);

        vm.prank(bob);
        assertTrue(single.transferFrom(deployer, alice, amount));
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, first));
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, amount - first));

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(deployer), single.balanceOf(deployer));
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.allowance(deployer, bob), single.allowance(deployer, bob));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function _state(address owner, address recipient, address spender) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                token.totalSupply(),
                token.balanceOf(deployer),
                token.balanceOf(owner),
                token.balanceOf(recipient),
                token.balanceOf(spender),
                token.balanceOf(address(0)),
                token.allowance(owner, spender)
            )
        );
    }
}
