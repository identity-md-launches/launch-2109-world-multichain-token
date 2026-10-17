// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployWorldToken} from "../script/DeployWorldToken.s.sol";
import {WorldToken} from "../src/WorldToken.sol";

contract DeployWorldTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    function test_deployFunctionMintsSupplyToTheScriptAsDeployer() public {
        DeployWorldToken script = new DeployWorldToken();
        WorldToken token = script.deploy();
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        // The script contract is `msg.sender` of the constructor, so it holds the supply.
        assertEq(token.balanceOf(address(script)), EXPECTED_SUPPLY);
        assertEq(token.name(), "World multichain token");
        assertEq(token.symbol(), "WORLD");
        assertEq(token.decimals(), 18);
    }
}
