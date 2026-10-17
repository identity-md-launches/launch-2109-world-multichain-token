// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title World multichain token (WORLD)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 WORLD (18 decimals) is minted
///         once, in the constructor, to the deployer (`msg.sender`). There is no owner, no minter,
///         no pause, no blocklist and no fee: after deployment the contract has no privileged role
///         and the supply can never grow.
/// @dev The contract name is `WorldToken` (the launch records contracts under their Solidity name,
///      at most 32 characters); the token's own name and symbol are returned by `name()` and
///      `symbol()`. The constructor takes no arguments and calls no other contract, so it deploys
///      on an empty chain. `msg.sender` at deployment is the launch factory, which then pays the
///      supply out (swarm share, pool seed, remainder) according to the launch economics.
contract WorldToken is ERC20 {
    /// @notice The token name returned by `name()`.
    string public constant TOKEN_NAME = "World multichain token";

    /// @notice The token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "WORLD";

    /// @notice Number of decimals; the ERC20 base returns 18 and this constant documents it.
    uint8 public constant DECIMALS = 18;

    /// @notice The entire supply ever to exist, in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Emitted once, at deployment, naming the address that received the whole supply.
    /// @param deployer The `msg.sender` of the deployment transaction.
    /// @param supply The amount minted, equal to `TOTAL_SUPPLY`.
    event SupplyMinted(address indexed deployer, uint256 supply);

    /// @notice Mints `TOTAL_SUPPLY` to the deployer. This is the only mint that ever happens.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }
}
