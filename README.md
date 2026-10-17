# World multichain token (WORLD)

A fixed-supply ERC-20 for an IMD custom token launch on Ethereum mainnet (chain id 1).

| Property | Value |
| --- | --- |
| Solidity contract name | `WorldToken` (`src/WorldToken.sol`) |
| `name()` | `World multichain token` |
| `symbol()` | `WORLD` |
| `decimals()` | 18 |
| Total supply | 1,000,000,000 WORLD = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minting | once, in the constructor, the whole supply to `msg.sender` |
| Owner / admin | none |

## Behaviour

- The constructor mints `TOTAL_SUPPLY` (1e9 × 1e18) to `msg.sender` and emits the standard
  `Transfer(0x0, deployer, supply)` plus a `SupplyMinted(deployer, supply)` event.
- The contract is OpenZeppelin `ERC20` (v5.4.0, vendored) with nothing added: plain `transfer`,
  `transferFrom`, `approve`, `allowance`, `balanceOf`, `totalSupply` and metadata.
- There is no mint, burn, pause, blocklist, freeze, fee, tax, reflection, owner, upgrade hook or
  `receive`/`fallback`. The supply can never grow and no privileged address can move or freeze a
  holder's balance. The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.
- Transfers to the zero address, transfers above balance, and `transferFrom` above allowance revert
  with the OpenZeppelin ERC-6093 custom errors.

## Assumptions

- "The deployer" is `msg.sender` of the deployment transaction. Under the IMD launch that is the
  ProjectFactory, which then distributes the supply according to the launch economics. The contract
  does not use `tx.origin` and does not reference the factory, pool manager or distributor: since it
  has no fee or restriction on any transfer, no exemptions are needed and no launch addresses are
  taken as constructor arguments.
- The constructor calls no other contract and needs no address to have code, so it deploys on an
  empty chain. It takes zero arguments (the limit is 16).
- Nothing in the brief asks for any transfer rule, so none was added. Adding one later means a new
  contract and a new launch; this token is immutable.
- "Multichain" is part of the name only. This contract carries no bridging or cross-chain logic;
  any other-chain representation would be a separate deployment or a bridge-wrapped asset outside
  this repository.

## Deployment parameters

The IMD launch deploys the token from the built bytecode and records it under its Solidity name.
Values the launch fixes (not open questions; recorded here for reviewers):

| Setting | Value |
| --- | --- |
| Chain | Ethereum, chain id 1 |
| `token.contract` | `WorldToken` |
| `token.decimals` | 18 |
| `token.totalSupply` | `1000000000000000000000000000` |
| `token.constructorArgs` | `[]` |
| Pair currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| `pool.fee` | 12500 (1.25%) |
| `pool.tickSpacing` | 60 |
| `pool.initialPrice` | `79228162514264337593543950336` (provenance only; the deployer derives the opening price) |
| `economics.poolBps` | 8000 |
| `economics.initialMarketCapWei` | `4500000000000000000000` (4,500 IMD for the whole supply) |
| `economics.remainderTo` | `0x0f44a55663e888bb63618a0c31b68cbc6c01aa71` |

Supply split performed by the factory at launch (none of it is encoded in the token):

- 10% to the launch's MerkleDistributor (the swarm's share);
- 80% seeds the single-sided WORLD/IMD Uniswap v4 pool;
- 10% to `economics.remainderTo`.

`launch.json` is written by the manifest step after acceptance; it is deliberately not in this tree.

Named constants chosen by this implementation (all taken directly from the brief, nothing open):
`TOKEN_NAME`, `TOKEN_SYMBOL`, `DECIMALS = 18`, `TOTAL_SUPPLY = 1_000_000_000 * 10**18`.

### Reference deploy script

`script/DeployWorldToken.s.sol` is a reviewable reference only. `run()` broadcasts one `new
WorldToken()` with whatever account the caller supplies; `deploy()` is the function tests call
directly. It reads no environment variables. This repository authorises no transaction and holds no
keys; the IMD deployer performs the real launch through the factory.

```sh
# local reproduction on an anvil fork or devnet; the broadcasting account receives the supply
forge script script/DeployWorldToken.s.sol --rpc-url <rpc> --broadcast --sender <addr> --private-key <key>
```

## After launch

There is nothing to configure. The token has no owner and no setters. Operational responsibilities:

- **Supply custody.** Whoever holds tokens after the factory's distribution (the distributor, the
  pool, `remainderTo`) is responsible for them; the contract cannot recover, freeze or reassign them.
- **Allowance hygiene.** Holders should grant bounded allowances; an unlimited approval persists
  until overwritten.
- **Explorer verification.** Source verification on Etherscan is the deployer's step after the
  launch (`forge verify-contract` with compiler 0.8.26, optimizer 200 runs, `bytecode_hash = none`,
  `cbor_metadata = false`, EVM version cancun).
- **No upgrade path.** A change of any kind means a new contract and a migration; plan accordingly.

## Build and test

```sh
forge build
forge test
forge fmt --check
```

Compiler pinned to `solc = "0.8.26"` in `foundry.toml`, `bytecode_hash = "none"`, no `ffi`, no
`fs_permissions`. Dependencies are vendored as ordinary files under `lib/` (no submodules):

- `lib/forge-std` — forge-std v1.11.0 (`src/` plus licences).
- `lib/openzeppelin-contracts` — OpenZeppelin Contracts v5.4.0, only the files `ERC20` needs:
  `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol`.

Tests (`test/`):

- `WorldToken.t.sol` — metadata, supply and recipient (including a contract deployer, where the
  supply must land on `msg.sender` and not `tx.origin`), constructor events, successful transfers
  and allowances, failing transfers (insufficient balance, zero receiver, missing or exceeded
  allowance, deployer pulling without approval), absence of every admin selector a launch floor
  probes, no `receive`/`fallback`, bytecode opcode scan, and fuzz tests for conservation of supply,
  over-balance reverts, allowance bounds and round trips.
- `WorldToken.invariant.t.sol` — a handler drives random transfers, approvals and `transferFrom`s;
  invariants: total supply never changes and balances always sum to it.
- `DeployWorldToken.t.sol` — the script's `deploy()` function mints the supply to the caller.

Tests read and set no environment variables and pass in any order and in parallel. The fuzz seed
the verifier uses (`FOUNDRY_FUZZ_SEED=0x4ae181904fb4a39f8903f42b9c625161b016615eff6fdefed73eda4564b1984f`)
was used for the local run.

## Security notes

Checked against the eth-security checklist supplied with the task: no external calls, no ETH
handling, no reentrancy surface, no oracle, no decimals arithmetic beyond the supply constant, no
`tx.origin`, no `selfdestruct`, no delegatecall, no upgradeability, no owner. Tooling run: `forge
build`, `forge test` (unit, fuzz, invariant), `forge fmt --check`. Slither and Mythril were not run
(not provided in this environment). Passing tests are not an audit; an independent adversarial
review is the launch's separate step.
