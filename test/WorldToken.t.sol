// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WorldToken} from "../src/WorldToken.sol";

/// @notice Deploys the token from a contract, the way the launch factory does, so the test can check
///         that `msg.sender` (and not `tx.origin` or anyone else) receives the supply.
contract FactoryProbe {
    function deploy() external returns (WorldToken) {
        return new WorldToken();
    }
}

/// @notice A holder that never receives tokens unless the test moves some to it.
contract HolderProbe {}

/// forge-config: default.fuzz.runs = 1000
contract WorldTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    WorldToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SupplyMinted(address indexed deployer, uint256 supply);

    function setUp() public {
        vm.prank(deployer);
        token = new WorldToken();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "World multichain token");
        assertEq(token.symbol(), "WORLD");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "World multichain token");
        assertEq(token.TOKEN_SYMBOL(), "WORLD");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_wholeSupplyMintedToDeployer() public view {
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintAndSupplyMintedEvents() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, EXPECTED_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(alice, EXPECTED_SUPPLY);
        vm.prank(alice);
        new WorldToken();
    }

    /// @dev The launch factory deploys the token from a contract call, so the supply must land on
    ///      `msg.sender` (the factory), not on `tx.origin` (the launch wallet).
    function test_supplyGoesToTheCallingContractNotTxOrigin() public {
        FactoryProbe factory = new FactoryProbe();
        vm.prank(alice, alice);
        WorldToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_eachDeploymentMintsItsOwnFullSupply() public {
        vm.prank(bob);
        WorldToken second = new WorldToken();
        assertEq(second.totalSupply(), EXPECTED_SUPPLY);
        assertEq(second.balanceOf(bob), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    // ---------------------------------------------------------------- transfers (success)

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, 1_000 ether);
        assertTrue(token.transfer(alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, EXPECTED_SUPPLY));
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5 ether));
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_transferToContractHolderSucceeds() public {
        HolderProbe holder = new HolderProbe();
        vm.prank(deployer);
        assertTrue(token.transfer(address(holder), 7 ether));
        assertEq(token.balanceOf(address(holder)), 7 ether);
    }

    function test_secondaryTransferIsUntaxed() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------- transfers (failure)

    function test_transferRevertsWhenBalanceInsufficient() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferRevertsWhenOverBalanceByOne() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        token.transfer(bob, 10 ether + 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
    }

    // ---------------------------------------------------------------- allowances

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 50 ether);
        assertTrue(token.approve(alice, 50 ether));
        assertEq(token.allowance(deployer, alice), 50 ether);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 50 ether);
        token.approve(alice, 5 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 5 ether);
    }

    function test_approveZeroAddressSpenderReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 50 ether);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 20 ether));
        assertEq(token.balanceOf(bob), 20 ether);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 20 ether);
        assertEq(token.allowance(deployer, alice), 30 ether);
    }

    function test_transferFromWithInfiniteAllowanceDoesNotDecrease() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 20 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1 ether));
        token.transferFrom(deployer, bob, 1 ether);
    }

    function test_transferFromRevertsAboveAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 10 ether, 11 ether)
        );
        token.transferFrom(deployer, bob, 11 ether);
    }

    function test_transferFromRevertsWhenOwnerBalanceInsufficient() public {
        vm.prank(alice);
        token.approve(bob, 100 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        token.transferFrom(alice, deployer, 1 ether);
    }

    /// @dev Nobody can pull a holder's tokens without that holder's approval, not even the deployer.
    function test_deployerCannotTransferFromHolderWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1 ether));
        token.transferFrom(alice, deployer, 1 ether);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    // ---------------------------------------------------------------- no privileged surface

    /// @dev Every admin-style selector a launch floor probes must be absent: the calls revert and
    ///      neither the supply nor any balance changes, whoever sends them.
    function test_noAdminFunctionsExist() public {
        address attacker = makeAddr("attacker");
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        string[22] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        address[2] memory callers = [attacker, deployer];
        for (uint256 i = 0; i < signatures.length; i++) {
            // Use valid ABI arguments: an invalid bool would revert in the decoder even if
            // a privileged function existed, hiding the very surface this test probes.
            bytes memory data;
            if (i == 2 || i == 8 || i == 10 || i == 18) {
                data = abi.encodeWithSignature(signatures[i]);
            } else if (i == 1 || i == 3) {
                data = abi.encodeWithSignature(signatures[i], uint256(1));
            } else if (i == 15 || i == 16) {
                data = abi.encodeWithSignature(signatures[i], alice, true);
            } else if (i == 19) {
                data = abi.encodeWithSignature(signatures[i], false);
            } else if (i == 0 || i == 20) {
                data = abi.encodeWithSignature(signatures[i], alice, uint256(1));
            } else {
                data = abi.encodeWithSignature(signatures[i], alice);
            }
            for (uint256 c = 0; c < callers.length; c++) {
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
            }
            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
            assertEq(token.balanceOf(alice), 1 ether, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
        // The holder still moves freely afterwards.
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1 ether));
        assertEq(token.balanceOf(bob), 1 ether);
    }

    function test_noOwnerFunction() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok);
    }

    function test_unknownCalldataAndPlainEthReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------- fuzz and invariants

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        to = address(uint160(bound(uint256(uint160(to)), 1, type(uint160).max)));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 excess) public {
        held = bound(held, 0, EXPECTED_SUPPLY - 1);
        excess = bound(excess, 1, EXPECTED_SUPPLY - held);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, held + excess)
        );
        token.transfer(bob, held + excess);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 spend) public {
        allowed = bound(allowed, 0, EXPECTED_SUPPLY);
        spend = bound(spend, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        if (spend > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowed, spend)
            );
            token.transferFrom(deployer, bob, spend);
        } else {
            assertTrue(token.transferFrom(deployer, bob, spend));
            assertEq(token.balanceOf(bob), spend);
            assertEq(token.allowance(deployer, alice), allowed - spend);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_roundTripLeavesBalancesUnchanged(uint256 amount) public {
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
