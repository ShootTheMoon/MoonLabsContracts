// SPDX-License-Identifier: UNLICENSED

/**
 * ███╗   ███╗ ██████╗  ██████╗ ███╗   ██╗    ██╗      █████╗ ██████╗ ███████╗
 * ████╗ ████║██╔═══██╗██╔═══██╗████╗  ██║    ██║     ██╔══██╗██╔══██╗██╔════╝
 * ██╔████╔██║██║   ██║██║   ██║██╔██╗ ██║    ██║     ███████║██████╔╝███████╗
 * ██║╚██╔╝██║██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══██║██╔══██╗╚════██║
 * ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║ ╚████║    ███████╗██║  ██║██████╔╝███████║
 * ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝
 * Moon Labs LLC reserves all rights on this code.
 * You may not, except otherwise with prior permission and express written consent by Moon Labs LLC, copy, download, print, extract, exploit,
 * adapt, edit, modify, republish, reproduce, rebroadcast, duplicate, distribute, or publicly display any of the content, information, or material
 * on this smart contract for non-personal or commercial purposes, except for any other use as permitted by the applicable copyright law.
 *
 * This is for ERC20 tokens and should NOT be used for Uniswap LP tokens or ANY other token protocol.
 *
 * Website: https://www.moonlabs.site/
 */

/**
 * @title This is a contract used for creating whitelists for Moon Labs products
 * @author Moon Labs LLC
 * @notice This contracts intended purpose is for users to purchase whitelist for their desired tokens. Whitelisting a token allows for all fees on
 * related Moon Labs products to be waived. Whitelists can not be transfered from tokent to token.
 */

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMoonLabsReferral {
  function checkIfActive(string calldata code) external view returns (bool);

  function getAddressByCode(string memory code) external view returns (address);

  function addRewardsEarnedUSD(string calldata code, uint commission) external;
}

interface IMoonLabsWhitelist {
  function getIsWhitelisted(address _address) external view returns (bool);
}

contract MoonLabsWhitelist is IMoonLabsWhitelist, Ownable {
  constructor(address _usdAddress, uint _costUSD) {
    usdAddress = _usdAddress;
    costUSD = _costUSD;
    usdContract = IERC20(_usdAddress);
  }

  /*|| === STATE VARIABLES === ||*/
  uint public nonce; /// Number of tokens whitelisted
  uint public costUSD; /// Cost in USD
  address public usdAddress; /// Address of desired USD token
  uint32 public codeDiscount; /// Discount in the percentage applied to the customer when using referral code, represented in 10s
  uint32 public codeCommission; /// Percentage of each lock purchase sent to referral code owner, represented in 10s
  IERC20 public usdContract;
  IMoonLabsReferral public referralContract; /// Moon Labs referral contract

  /*|| === MAPPINGS === ||*/
  mapping(address => bool) tokenToWhitelist;

  /*|| === EXTERNAL FUNCTIONS === ||*/
  /**
   * @notice Purchase a whitelist for a single token.
   * @param _address Token address to be whitelisted
   */
  function addToWhitelist(address _address) external {
    require(!getIsWhitelisted(_address), "Token already whitelisted");
    require(usdContract.balanceOf(msg.sender) >= costUSD, "Insignificant balance");
    usdContract.transferFrom(msg.sender, address(this), costUSD);
    /// Add token to global whitelist
    tokenToWhitelist[_address] = true;
  }

  /**
   * @notice Purchase a whitelist for a single token using a referral code.
   * @param _address Token address to be whitelisted
   * @param code Referral code
   */
  function addToWhitelistWhiteCode(address _address, string calldata code) external {
    require(!getIsWhitelisted(_address), "Token already whitelisted");
    /// Check for referral valid code
    require(referralContract.checkIfActive(code), "Invalid code");
    require(usdContract.balanceOf(msg.sender) >= (costUSD * codeDiscount) / 100, "Insignificant balance");
    usdContract.transferFrom(msg.sender, address(this), (costUSD * codeDiscount) / 100);
    /// Distribute commission
    distributeCommission(code, (costUSD * codeCommission) / 100);
    /// Add token to global whitelist
    tokenToWhitelist[_address] = true;
  }

  /*|| === PUBLIC FUNCTIONS === ||*/
  /**
   * @notice Check to see if a token is whitelisted.
   * @param _address Token address to check if whitelisted
   */
  function getIsWhitelisted(address _address) public view override returns (bool) {
    if (tokenToWhitelist[_address]) return true;
    return false;
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  /**
   * @notice Distribute commission to referral code owner.
   * @param code Referral code used
   * @param commission Amount in USD tokens to be distributed
   */
  function distributeCommission(string calldata code, uint commission) private {
    /// Send USD to referral code owner
    usdContract.transfer(referralContract.getAddressByCode(code), commission);
    /// Log rewards in the referral contract
    referralContract.addRewardsEarnedUSD(code, commission);
  }
}
