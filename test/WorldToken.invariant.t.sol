// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldToken} from "../src/WorldToken.sol";

/// @notice Drives the token with random transfers, approvals and transferFroms between a fixed set
///         of actors, so the invariant test can check that the supply never changes and balances
///         always sum to it. Ghost balances and allowances are derived from requested actions,
///         never copied from the token, so conservation cannot hide a transfer to the wrong actor.
contract WorldTokenHandler is Test {
    WorldToken public immutable token;
    address[] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    constructor(WorldToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = EXPECTED_SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Deliberately reach revocation, infinite approval, the largest finite approval,
        // and finite allowances that can actually be exhausted within this fixed supply.
        uint256 mode = amount % 5;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        else amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 cap = expectedBalance[owner];
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed < cap) cap = allowed;
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        _recordSpend(owner, spender, to, amount);
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        uint256 amount = held + bound(excess, 1, type(uint256).max - held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: every balance and allowance must survive a rejected call intact.
    }

    /// @dev Unbounded amounts complement the success-only handler. Classify the result using
    ///      the independent ledger, including failures after allowance spending would begin.
    function transferFromUnbounded(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 held = expectedBalance[owner];
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else if (amount > held) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else {
            vm.prank(spender);
            assertTrue(token.transferFrom(owner, to, amount));
            _recordSpend(owner, spender, to, amount);
        }
    }

    function transferToZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 cap = expectedBalance[owner];
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed < cap) cap = allowed;
        amount = bound(amount, 0, cap);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _recordSpend(address owner, address spender, address to, uint256 amount) internal {
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        _recordTransfer(owner, to, amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract WorldTokenInvariantTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    WorldToken internal token;
    WorldTokenHandler internal handler;
    address[] internal actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new WorldToken();

        actors.push(deployer);
        actors.push(makeAddr("a"));
        actors.push(makeAddr("b"));
        actors.push(makeAddr("c"));
        actors.push(makeAddr("d"));
        handler = new WorldTokenHandler(token, actors);

        // Fund every actor through real transfers so successful nonzero calls are reachable
        // from the start. The deployer still received the entire constructor mint.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, EXPECTED_SUPPLY / actors.length);
        }

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = WorldTokenHandler.transfer.selector;
        selectors[1] = WorldTokenHandler.approve.selector;
        selectors[2] = WorldTokenHandler.revoke.selector;
        selectors[3] = WorldTokenHandler.transferFrom.selector;
        selectors[4] = WorldTokenHandler.transferAboveBalance.selector;
        selectors[5] = WorldTokenHandler.transferFromUnbounded.selector;
        selectors[6] = WorldTokenHandler.transferToZero.selector;
        selectors[7] = WorldTokenHandler.transferFromToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, EXPECTED_SUPPLY);
    }

    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "actor balance mismatch");
        }
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
    }

    function invariant_allowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance changed without approval or successful spending"
                );
            }
        }
    }
}
