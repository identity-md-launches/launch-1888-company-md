// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "../src/CompanyToken.sol";

/// @dev Handler calls check both successful operations and expected token rejections.
/// Only these actors receive tokens, so their aggregate balance must equal the total supply.
contract CompanyTokenHandler is Test {
    CompanyToken public immutable token;
    address[4] public actors;
    // Initialized from the specification and updated from requested actions, never resynced
    // from token getters. Comparing every entry also catches changes to unrelated accounts.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(CompanyToken token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
        }
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundarySeed) external {
        uint256[6] memory amounts = [uint256(0), 1, 1e27, 1e27 + 1, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[boundarySeed % 6]);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        _recordTransfer(from, to, amount);
        if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        assertEq(token.allowance(from, spender), allowed == type(uint256).max ? allowed : allowed - amount);
    }

    function rejectTransferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferFromOverBalance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        // Make the balance the only failing precondition; finite allowance spending must roll back.
        _approve(from, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectTransferFromOverAllowance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 allowanceSeed,
        uint256 amountSeed
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = bound(allowanceSeed, 0, type(uint256).max - 1);
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        _approve(from, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroRecipient(uint256 fromSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance[from];
        if (delegated && expectedAllowance[from][spender] < limit) limit = expectedAllowance[from][spender];
        uint256 amount = bound(amountSeed, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : from);
        if (delegated) token.transferFrom(from, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract CompanyTokenInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    CompanyToken private token;
    CompanyTokenHandler private handler;

    function setUp() public {
        token = new CompanyToken();
        handler = new CompanyTokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = CompanyTokenHandler.transfer.selector;
        selectors[1] = CompanyTokenHandler.approve.selector;
        selectors[2] = CompanyTokenHandler.transferFrom.selector;
        selectors[3] = CompanyTokenHandler.approveBoundary.selector;
        selectors[4] = CompanyTokenHandler.rejectTransferOverBalance.selector;
        selectors[5] = CompanyTokenHandler.rejectTransferFromOverBalance.selector;
        selectors[6] = CompanyTokenHandler.rejectTransferFromOverAllowance.selector;
        selectors[7] = CompanyTokenHandler.rejectZeroRecipient.selector;
        selectors[8] = CompanyTokenHandler.rejectZeroSpender.selector;
        selectors[9] = CompanyTokenHandler.revokeAndRejectSpend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesRemainConserved() public view {
        uint256 aggregate;
        for (uint256 i; i < 4; ++i) {
            aggregate += token.balanceOf(handler.actors(i));
        }
        assertEq(aggregate, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allBalancesAndAllowancesMatchActionHistory() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "balance differs from action history");
            assertEq(token.allowance(owner, address(0)), 0, "zero spender gained allowance");
            assertEq(token.allowance(address(0), owner), 0, "zero owner granted allowance");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance differs from action history"
                );
            }
        }
    }
}
