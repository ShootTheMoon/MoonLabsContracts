// SPDX-License-Identifier: MIT

/**
 * ███╗   ███╗ ██████╗  ██████╗ ███╗   ██╗    ██╗      █████╗ ██████╗ ███████╗
 * ████╗ ████║██╔═══██╗██╔═══██╗████╗  ██║    ██║     ██╔══██╗██╔══██╗██╔════╝
 * ██╔████╔██║██║   ██║██║   ██║██╔██╗ ██║    ██║     ███████║██████╔╝███████╗
 * ██║╚██╔╝██║██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══██║██╔══██╗╚════██║
 * ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║ ╚████║    ███████╗██║  ██║██████╔╝███████║
 * ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝
 */

/**
 * @title A token migration contract for Moon Labs
 * @author TG: @moondan1337
 */

pragma solidity 0.8.17;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MoonLabsMigrator is ReentrancyGuard, Ownable {
    /*|| === STATE VARIABLES === ||*/
    uint public maxDepositAmount; /// Max amount of tokens a wallet can deposit
    IERC20 public immutable tokenToDeposit; /// Token to send to the contract
    bool public enabled; /// Migration enabled

    /*|| === MAPPINGS === ||*/
    mapping(address => uint) public addressToAmount;

    /*|| === CONSTRUCTOR === ||*/
    constructor(address _tokenToDeposit) {
        tokenToDeposit = IERC20(_tokenToDeposit);
        enabled = true;
        maxDepositAmount = 1500000000000000;
    }

    /*|| === EVENTS === ||*/
    event Deposit(address indexed _address, uint amount);

    /*|| === PUBLIC FUNCTIONS === ||*/

    /**
     * @notice Returns amount of tokens left a single wallet can deposit.
     * @param _address address to check
     * @return amount amount of tokens left a the wallet can deposit
     */
    function getAvailableDepositLeft(
        address _address
    ) public view returns (uint amount) {
        return maxDepositAmount - addressToAmount[_address];
    }

    /*|| === EXTERNAL FUNCTIONS === ||*/
    /**
     * @notice Deposits all of old tokens into the contract. Checks if wallet had exceeded max migration amount.
     * @dev to ensure migration continuity, the difference between the balance of the contract before and after tokens are deposited is the amount sent to the given address.
     */
    function depositAllTokens() external nonReentrant {
        require(enabled, "Migration not enabled");

        uint senderBalance = tokenToDeposit.balanceOf(msg.sender);

        require(senderBalance > 0, "Zero balance");
        require(
            senderBalance <= getAvailableDepositLeft(msg.sender),
            "Max deposit"
        );

        uint balanceBefore = tokenToDeposit.balanceOf(address(this));

        /// Transfer tokens from sender to contract
        tokenToDeposit.transferFrom(msg.sender, address(this), senderBalance);

        /// Log tokens received to use as value to transfer to _address.
        uint tokensRecieved = tokenToDeposit.balanceOf(address(this)) -
            balanceBefore;

        /// Map amount received to _address
        addressToAmount[msg.sender] += tokensRecieved;

        emit Deposit(msg.sender, tokensRecieved);
    }

    /**
     * @notice Claims all tokens deposited into the contract. Only owner function.
     */
    function claimDepositedTokens() external onlyOwner {
        /// Transfer all deposited tokens to owner
        tokenToDeposit.transfer(
            msg.sender,
            tokenToDeposit.balanceOf(address(this))
        );
    }

    /**
     * @notice Enable contract deposits. Only owner function.
     */
    function enable() external onlyOwner {
        require(enabled == false, "Already enabled");
        enabled = true;
    }

    /**
     * @notice Disable contract deposits. Only owner function.
     */
    function disable() external onlyOwner {
        require(enabled == true, "Already disabled");
        enabled = false;
    }

    /**
     * @notice Claim ETH in contract. Only owner function.
     */
    function claimETH() external onlyOwner {
        (bool sent, ) = payable(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice Returns number of deposited tokens in contract. Quality of life.
     */
    function tokenToDepositBalance() external view returns (uint) {
        return tokenToDeposit.balanceOf(address(this));
    }
}
