// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "src/CompanyToken.sol";

/// @dev Extends the deployment and ERC-20 tests with allowance transitions and arithmetic edges.
/// forge-config: default.fuzz.runs = 1000
contract CompanyTokenBoundaryTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CompanyToken private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    function setUp() public {
        token = new CompanyToken();
        holder = makeAddr("boundary holder");
        recipient = makeAddr("boundary recipient");
        spender = makeAddr("boundary spender");
        otherSpender = makeAddr("boundary other spender");
    }

    function test_oneBaseUnitRoundTripExhaustsAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), holder, 1);
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, address(this), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.allowance(holder, spender), 0);

        _expectAllowanceFailure(holder, spender, address(this), 0, 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferAmountFailsWithBalanceErrorAndPreservesUnlimitedAllowance() public {
        uint256 maximum = type(uint256).max;
        bytes memory reason =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(reason);
        token.transfer(recipient, maximum);
        vm.expectRevert(reason);
        token.transfer(address(this), maximum);

        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(address(this), recipient, maximum);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumMinusOneIsFiniteAndSwitchingAllowanceModesTakesEffect() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), 0);
        _expectAllowanceFailure(address(this), spender, holder, 0, 1);
        assertEq(token.balanceOf(holder), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_unlimitedApprovalCanBeRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertTrue(token.approve(spender, 0));
        _expectAllowanceFailure(address(this), spender, holder, 0, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(holder), 1);
    }

    function test_returningTokensDoesNotRestoreSpentAllowance() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, SUPPLY));
        vm.prank(holder);
        assertTrue(token.transfer(address(this), SUPPLY));
        _expectAllowanceFailure(address(this), spender, recipient, 0, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_multipleSpendersCannotSpendMoreThanTheOwnersBalance() public {
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.approve(otherSpender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), otherSpender), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        // The failed spend did not consume authorization; it works when the owner receives funds.
        vm.prank(holder);
        assertTrue(token.transfer(address(this), 1));
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), otherSpender), SUPPLY - 1);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_directTransfersLeaveExistingAllowancesUntouched() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.approve(otherSpender, type(uint256).max));
        assertTrue(token.transfer(holder, SUPPLY));
        assertEq(token.allowance(address(this), address(this)), 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(address(this), otherSpender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_ownerCanUseTransferFromWithExplicitSelfApproval() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _expectAllowanceFailure(address(this), address(this), recipient, 0, 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_zeroDelegatedTransferToZeroAddressStillReverts() public {
        uint256[3] memory approvals = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
        }
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroSpenderRejectedForZeroAndMaximumApprovals() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_approvalFromAnotherOwnerDoesNotAuthorizeSpendingThisOwnersTokens() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(holder);
        assertTrue(token.approve(otherSpender, type(uint256).max));
        _expectAllowanceFailure(address(this), otherSpender, recipient, 0, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(holder, otherSpender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_zeroDelegatedTransferEmitsEventWithoutChangingFiniteAllowance() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementIsIdempotent(uint256 first, uint256 replacement) public {
        // Approval does not require funds and is replacement, even above the supply.
        vm.startPrank(holder);
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowancesAboveSupplyRemainFinite(uint256 allowanceSeed, uint256 amountSeed) public {
        uint256 allowed = bound(allowanceSeed, SUPPLY + 1, type(uint256).max - 1);
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.allowance(address(this), spender), allowed - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedBalanceCheckPreservesAllowanceAndLaterSpendWorks(
        uint256 balanceSeed,
        uint256 amountSeed,
        bool unlimited
    ) public {
        uint256 balance = bound(balanceSeed, 1, SUPPLY);
        uint256 attempted = bound(amountSeed, balance + 1, type(uint256).max - 1);
        uint256 allowed = unlimited ? type(uint256).max : attempted;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, allowed));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, attempted)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, attempted);
        assertEq(token.allowance(holder, spender), allowed);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, balance));
        assertEq(token.allowance(holder, spender), unlimited ? allowed : allowed - balance);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitDelegatedSpendsEqualOneSpend(uint256 totalSeed, uint256 firstSeed) public {
        uint256 total = bound(totalSeed, 1, SUPPLY);
        uint256 first = bound(firstSeed, 0, total);
        assertTrue(token.approve(spender, total));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, first));
        assertEq(token.allowance(address(this), spender), total - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, total - first));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.balanceOf(recipient), total);
        _expectAllowanceFailure(address(this), spender, recipient, 0, 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferConsumesOnlyAllowance(uint256 allowanceSeed, uint256 amountSeed) public {
        uint256 allowed = bound(allowanceSeed, 0, type(uint256).max - 1);
        uint256 amount = bound(amountSeed, 0, allowed < SUPPLY ? allowed : SUPPLY);
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), amount));
        assertEq(token.allowance(address(this), spender), allowed - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _expectAllowanceFailure(address from, address caller, address to, uint256 allowed, uint256 amount)
        private
    {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, allowed, amount)
        );
        vm.prank(caller);
        token.transferFrom(from, to, amount);
    }
}
