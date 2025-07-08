//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;
import {IRebaseToken} from "./interface/IRebaseToken.sol";

contract Vault {
    IRebaseToken private immutable i_rebaseToken;
    //we need to pass the token address to the constructor
    //we need a deposite function that mints tokens to the user and equal to the amount of ether the user has sent
    //create a redeem function that burns tokens from the user and send the user ether
    //create a way to add reward to the vault 
    
    event Deposited(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault_RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}
/**
 * @notice allow user to deposte ETH into the vault and mint rebase in return
 * 
 */
    function deposite() external payable {
        //1. we need to use the amount of ETH the user has sent to mint tokens to the user
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposited (msg.sender, msg.value);
    }

    function redeem(uint256 _amount)external {
        //1. we need to brun the token from the user
        if(_amount == type(uint256).max){
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender,_amount);
        //2. send the user ether
        (bool success,)=payable(msg.sender).call{value: _amount}("");
        if(!success){
            revert Vault_RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
        
    }
    /**
     * @notice get the address of rebase token and return it 
     */

    function getRebaseToken() external view returns (address) {
        return address(i_rebaseToken);
    }

}