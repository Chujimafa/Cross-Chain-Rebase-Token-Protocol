//SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @notice this contract is a cross-chain rebase token that incentivises users to deposite into a vault to
 * and gain interests in rewards
 * @notice the interest rate in the samrt contract can only decrease
 * @notice each user will have their own interest rate that is the global interetst rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken_InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    //uint256 private s_interestRate=5e10; //1. `(5e10 / 1e18) = 0.00000005` or `0.000005%` per second
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event intererRateSet(uint256 indexed newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @dev Sets the interest rate
     * @param _newInterestRate the new interest rate to set
     * @dev the interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        //set interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken_InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit intererRateSet(_newInterestRate);
    }

    /**
     * @notice mint the user tokens when they deposit into the vault
     * @param _to the user to mint token to
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice burn the user tokens when they withdraw from the vault
     * @param _from the user to burn token from
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice calculate the balance of the user including any interest accrued since the last update
     * (principal balance) + some interest that has accrued
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //get the current principal balance (the number of tokens that have actually been minted to the user )
        //balancOf (function from ERC20, mapping _balance )
        //multiply the principal balance by the interest rate that has accumulated in the time
        //since the balance was updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
        // if donnot add super, it will call the recursive self function
    }

    /**
     * @notice Transfer tokens from one user to another
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @notice let spender get approve to transfer from one user to another
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice calculate the interest that has accrued since the last update
     * return the interest that has accumulated since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        //we need to calculate the interest that has accumulated since the last update
        //this is going to linear growth with time
        //1. calculate the time since the last update
        //2. calculate the amount of linear growth
        //deposite:10 tokens, interest rate 0.5 token per second
        // time elapsed: 2s,
        //balance: 10+10*0.5*2=20
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }
    /**
     * @notice mint the accured interest to the user since last time they interacted with the protocol
     * (mint, transfer, burn, etc. )
     */

    function _mintAccruedInterest(address _user) internal {
        //1. find the balance of current rebase token which have been minted to the user -> principal balance
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        // 2. calculate their current balance including any interest accrued-> return from balanceOf
        uint256 currentBalance = balanceOf(_user);
        //calculate the number of tokens that need to be minted to the user -> interest （2）-（1）
        uint256 interestAccrued = currentBalance - previousPrincipalBalance;
        //mint the interest to the user
        //set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint to the user
        _mint(_user, interestAccrued);
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Get the interest rate that is currently set for the contract.
     * Any future deposite will save this interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice this is the number of token that have currently been minted to user,
     * the number not included any interest that has accured since the last time the user interacted with the protocol
     *
     */
    function principalBalance(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
}
