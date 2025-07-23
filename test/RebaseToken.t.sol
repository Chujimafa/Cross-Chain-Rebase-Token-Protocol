//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interface/IRebaseToken.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public SEND_VALUE = 1e5;

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardsAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardsAmount}("");
    }

    function testDepositeLiniear(uint256 amount) public {
        //vm.assume(amount>1e5);//if smaller than 1e5, the test will diacard
        amount = bound(amount, 1e5, type(uint96).max);
        //1. deposite
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposite{value: amount}();
        //2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);
        //3. warp time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        //4. warp time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);
        //check the linie interest
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        //deposite
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposite{value: amount}();
        assertEq(amount, rebaseToken.balanceOf(user));
        console.log("amount:", amount, "Balance:", rebaseToken.balanceOf(user));
        //check the balance is same the amount deposited
        //redeem
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(amount, address(user).balance);
        console.log("amount:", amount, "addressBalance:", address(user).balance);
        vm.stopPrank();
    }

    function testRedeemAfterTimePasses(uint256 depositeAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositeAmount = bound(depositeAmount, 1e5, type(uint96).max);

        //deposite

        vm.deal(user, depositeAmount);
        vm.prank(user);
        vault.deposite{value: depositeAmount}();
        //warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        //redeem
        //(b) add the rewards to the vault
        vm.deal(owner, balanceAfterSomeTime - depositeAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositeAmount);

        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositeAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        //1. deposite
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposite{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        //owner reduce the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        //2. transfer
        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        //check the interest rate has been inherited(5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRateIfNotOwner(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.startPrank(user);
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.expectRevert();
        rebaseToken.mint(user, 1e4, interestRate);
        vm.expectRevert();
        rebaseToken.burn(user, 1e4);
        vm.stopPrank();
    }

    function testGetPricipalAmount(uint256 amount) public {
        amount = bound(amount, 2e5, type(uint96).max);
        //deposite
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposite{value: amount}();
        assertEq(rebaseToken.principalBalance(user), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalance(user), amount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseToken(), address(rebaseToken));
    }

    function testIntereseRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken_InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(initialInterestRate, rebaseToken.getInterestRate());
    }
}
