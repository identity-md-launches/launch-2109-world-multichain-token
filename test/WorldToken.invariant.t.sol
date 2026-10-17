// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {WorldToken} from "../src/WorldToken.sol";

/// @notice Drives the token with random transfers, approvals and transferFroms between a fixed set
///         of actors, so the invariant test can check that the supply never changes and balances
///         always sum to it.
contract WorldTokenHandler is Test {
    WorldToken public immutable token;
    address[] public actors;

    constructor(WorldToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        token.approve(spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 cap = token.balanceOf(owner);
        uint256 allowed = token.allowance(owner, spender);
        if (allowed < cap) cap = allowed;
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }
}

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
}
