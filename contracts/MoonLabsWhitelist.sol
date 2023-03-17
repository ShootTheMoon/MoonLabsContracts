// SPDX-License-Identifier: UNLICENSED

/**
 * ███╗   ███╗ ██████╗  ██████╗ ███╗   ██╗    ██╗      █████╗ ██████╗ ███████╗
 * ████╗ ████║██╔═══██╗██╔═══██╗████╗  ██║    ██║     ██╔══██╗██╔══██╗██╔════╝
 * ██╔████╔██║██║   ██║██║   ██║██╔██╗ ██║    ██║     ███████║██████╔╝███████╗
 * ██║╚██╔╝██║██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══██║██╔══██╗╚════██║
 * ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║ ╚████║    ███████╗██║  ██║██████╔╝███████║
 * ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝
 *
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
 * @notice  This contract's intended purpose is for users to purchase whitelists for their desired tokens. Whitelisting a token allows for all fees on
 * related Moon Labs products to be waived. Whitelists may not be transferred from token to token.
 */

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./IDEXRouter.sol";

interface IMoonLabsReferral {
  function checkIfActive(string calldata code) external view returns (bool);

  function getAddressByCode(string memory code) external view returns (address);

  function addRewardsEarnedUSD(string calldata code, uint commission) external;
}

interface IMoonLabsWhitelist {
  function getIsWhitelisted(address _address) external view returns (bool);
}

contract MoonLabsWhitelist is Initializable, IMoonLabsWhitelist, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  function initialize(address _usdAddress, uint _costUSD) public initializer {
    __Ownable_init();
    usdAddress = _usdAddress;
    costUSD = _costUSD;
    usdContract = IERC20Upgradeable(_usdAddress);
    codeDiscount = 10;
    codeCommission = 10;
  }

  /*|| === STATE VARIABLES === ||*/
  uint public costUSD; /// Cost in USD
  address public usdAddress; /// Address of desired USD token
  uint32 public codeDiscount; /// Discount in the percentage applied to the customer when using referral code, represented in 10s
  uint32 public codeCommission; /// Percentage of each lock purchase sent to referral code owner, represented in 10s
  IERC20Upgradeable public usdContract; /// Select USD contract
  IMoonLabsReferral public referralContract; /// Moon Labs referral contract

  /*|| === MAPPINGS === ||*/
  mapping(address => bool) tokenToWhitelist;

  /*|| === EXTERNAL FUNCTIONS === ||*/
  /**
   * @notice Purchase a whitelist for a single token.
   * @param _address Token address to be whitelisted
   */
  function purchaseWhitelist(address _address) external {
    require(!getIsWhitelisted(_address), "Token already whitelisted");
    require(usdContract.balanceOf(msg.sender) >= costUSD, "Insignificant balance");

    usdContract.safeTransferFrom(msg.sender, address(this), costUSD);
    /// Add token to global whitelist
    tokenToWhitelist[_address] = true;
  }

  /**
   * @notice Purchase a whitelist for a single token using a referral code.
   * @param _address Token address to be whitelisted
   * @param code Referral code
   */
  function purchaseWhitelistWithCode(address _address, string calldata code) external {
    require(!getIsWhitelisted(_address), "Token already whitelisted");
    /// Check for referral valid code
    require(referralContract.checkIfActive(code), "Invalid code");
    /// Check for significant balance
    require(usdContract.balanceOf(msg.sender) >= costUSD - (costUSD * codeDiscount) / 100, "Insignificant balance");
    /// Transfer tokens from caller to contract
    usdContract.safeTransferFrom(msg.sender, address(this), costUSD - (costUSD * codeDiscount) / 100);
    /// Distribute commission to code owner
    distributeCommission(code, (costUSD * codeCommission) / 100);
    /// Add token to global whitelist
    tokenToWhitelist[_address] = true;
  }

  /**
   * @notice Add to whitelist without fee. Owner only function.
   * @param _address Token address to be whitelisted
   */
  function ownerWhitelistAdd(address _address) external onlyOwner {
    /// Add token to global whitelist
    tokenToWhitelist[_address] = true;
  }

  /**
   * @notice Remove from whitelist. Owner only function.
   * @param _address Token address to be removed from whitelist
   */
  function ownerWhitelistRemove(address _address) external onlyOwner {
    /// Add token to global whitelist
    tokenToWhitelist[_address] = false;
  }

  /**
   * @notice Set the cost of each whitelist purchase. Owner only function
   * @param _costUSD Cost per whitelist
   */
  function setCostUSD(uint _costUSD) external onlyOwner {
    costUSD = _costUSD;
  }

  /**
   * @notice Set the percentage of ETH per lock discounted on code use. Owner only function.
   * @param _codeDiscount Percentage represented in 10s
   */
  function setCodeDiscount(uint8 _codeDiscount) external onlyOwner {
    require(_codeDiscount < 100, "Percentage ceiling");
    codeDiscount = _codeDiscount;
  }

  /**
   * @notice Set the percentage of ETH per lock distributed to the code owner. Owner only function.
   * @param _codeCommission Percentage represented in 10s
   */
  function setCodeCommission(uint8 _codeCommission) external onlyOwner {
    require(_codeCommission < 100, "Percentage ceiling");
    codeCommission = _codeCommission;
  }

  /**
   * @notice Send all eth in contract to caller. Owner only function.
   */
  function claimETH() external onlyOwner {
    (bool sent, ) = payable(msg.sender).call{ value: address(this).balance }("");
    require(sent, "Failed to send Ether");
  }

  /**
   * @notice Send all USD in contract to caller. Owner only function.
   */
  function claimUSD() external onlyOwner {
    usdContract.safeTransferFrom(address(this), msg.sender, usdContract.balanceOf(address(this)));
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
    /// Get balance before sending tokens
    uint previousBal = usdContract.balanceOf(address(this));

    /// Send USD to referral code owner
    usdContract.safeTransfer(referralContract.getAddressByCode(code), commission);

    /// Calculate amount sent based off before and after balance
    uint amountSent = usdContract.balanceOf(address(this)) - previousBal;

    /// Log rewards in the referral contract
    referralContract.addRewardsEarnedUSD(code, amountSent);
  }
}
