// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {WorldToken} from "../src/WorldToken.sol";

/// @title Deploy script for WorldToken
/// @notice Reviewable reference deployment. The IMD launch deploys the token itself from the built
///         bytecode through its factory; this script exists so a reviewer can reproduce a deployment
///         locally and so tests can exercise the deployment function directly. It reads no
///         environment variables: the token has no constructor arguments, and the deployer is
///         whichever account broadcasts.
contract DeployWorldToken is Script {
    /// @notice Deploys a new WorldToken. The caller of this function (under `vm.broadcast`, the
    ///         broadcasting account) receives the whole supply.
    function deploy() public returns (WorldToken token) {
        token = new WorldToken();
    }

    /// @notice Entry point for `forge script`. Broadcasts a single deployment.
    function run() external returns (WorldToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
