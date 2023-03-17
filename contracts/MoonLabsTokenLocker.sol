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
 * @title A token locker contract for ERC20 tokens.
 * @author Moon Labs LLC
 * @notice This contract's intended purpose is to allow users to create token locks for ERC20 tokens. Lock owners may change withdrawn address, extend, transfer, add to,
 * and split locks. The withdrawn address my withdrawn tokens from the lock but does not have any administartion powers over the lock iteself. Lock owners may NOT unlock
 * tokens prematurely for whatever reason. Lock creators may choose to create standard or linear locks. Tokens locked in this contract remain locked until their respective
 * unlock date without ANY exceptions. This contract is not suited to handle rebasing tokens or tokens in which a wallet's supply changes based on total supply.
 */

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./IDEXRouter.sol";

interface IMoonLabsReferral {
  function checkIfActive(string calldata code) external view returns (bool);

  function getAddressByCode(string memory code) external view returns (address);

  function addRewardsEarned(string calldata code, uint commission) external;
}

interface IMoonLabsWhitelist {
  function getIsWhitelisted(address _address) external view returns (bool);
}

contract MoonLabsTokenLocker is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  function initialize(address _tokenToBurn, address _feeCollector, address referralAddress, address whitelistAddress, address routerAddress) public initializer {
    __Ownable_init();
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
    feeCollector = _feeCollector;
    referralContract = IMoonLabsReferral(referralAddress);
    whitelistContract = IMoonLabsWhitelist(whitelistAddress);
    routerContract = IDEXRouter(routerAddress);
    ethLockPrice = .008 ether;
    ethSplitPrice = .004 ether;
    ethRelockPrice = .004 ether;
    burnThreshold = .25 ether;
    codeDiscount = 10;
    codeCommission = 10;
    burnPercent = 30;
    percentLockPrice = 30;
    percentSplitPrice = 15;
    percentRelockPrice = 15;
  }

  /*|| === STATE VARIABLES === ||*/
  uint public ethLockPrice; /// Price in WEI for each lock instance when paying for lock with ETH
  uint public ethSplitPrice; /// Price in WEI for each lock instance when splitting lock with ETH
  uint public ethRelockPrice; /// Price in WEI for each lock instance when relocking lock with ETH
  uint public burnThreshold; /// ETH in WEI when tokenToBurn should be bought and sent to DEAD address
  uint public burnMeter; /// Current ETH in WEI for buying and burning tokenToBurn
  address public feeCollector; /// Fee collection address for paying with token percent
  uint64 public nonce; /// Unique lock identifier
  uint8 public codeDiscount; /// Discount in the percentage applied to the customer when using referral code, represented in 10s
  uint8 public codeCommission; /// Percentage of each lock purchase sent to referral code owner, represented in 10s
  uint8 public burnPercent; /// Percent of each transaction sent to burnMeter, represented in 10s
  uint16 public percentLockPrice; /// Percent of deposited tokens taken for a lock that is paid for using tokens, represented in 10000s
  uint16 public percentSplitPrice; /// Percent of deposited tokens taken for a split that is paid for using tokens. represented in 10000s
  uint16 public percentRelockPrice; /// Percent of deposited tokens taken for a relock that is paid for using tokens. represented in 10000s
  IERC20Upgradeable public tokenToBurn; /// Native Moon Labs token
  IDEXRouter public routerContract; /// Uniswap router
  IMoonLabsReferral public referralContract; /// Moon Labs referral contract
  IMoonLabsWhitelist public whitelistContract; /// Moon Labs whitelist contract

  /*|| === STRUCTS VARIABLES === ||*/
  struct LockInstance {
    address tokenAddress; /// Address of locked token
    address ownerAddress; /// Address of owner
    address withdrawalAddress; /// Address of withdrawer
    uint depositAmount; /// Total deposit amount
    uint currentAmount; /// Current tokens in lock
    uint64 startDate; /// Date when tokens start to unlock, is a Linear lock if !=0.
    uint64 endDate; /// Date when all tokens are fully unlocked
  }

  struct LockParams {
    uint depositAmount;
    uint64 startDate;
    uint64 endDate;
    address ownerAddress;
    address withdrawalAddress;
  }

  /*|| === MAPPINGS === ||*/
  mapping(address => uint64[]) private ownerToLock; /// Owner address to array of locks
  mapping(address => uint64[]) private withdrawalToLock; /// Withdrawal address to array of locks
  mapping(address => uint64[]) private tokenToLock; /// Token address to array of locks
  mapping(uint64 => LockInstance) private lockInstance; /// Nonce to lock

  /*|| === EVENTS === ||*/
  event LockCreated(address creator, address token, uint64 numOfLocks, uint64 nonce);
  event TokensWithdrawn(address withdrawer, uint amount, uint64 nonce);
  event LockTransferred(address from, address to, uint64 nonce);
  event WithdrawalTransferred(address from, address to, uint64 nonce);
  event LockRelocked(address owner, uint amount, uint64 startTime, uint64 endTime, uint64 nonce);
  event LockSplit(address from, address to, uint amount, uint64 nonce, uint64 newNonce);

  /*|| === EXTERNAL FUNCTIONS === ||*/
  /**  
   * @notice Create one or multiple lock instances for a single token with no fees. Only available for whitelisted tokens.
   * @param tokenAddress Contract address of the erc20 token
   * @param locks array of LockParams struct(s) containing:
   *    ownerAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is a Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
    @dev Since this lock is free, no ETH is added to the burn meter. This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
  */
  function createLockWhitelist(address tokenAddress, LockParams[] calldata locks) external {
    /// Check if token is whitelisted
    require(whitelistContract.getIsWhitelisted(tokenAddress), "Not whitelisted");

    /// Calculate total deposit
    uint totalDeposited = calculateTotalDeposited(locks);

    /// Check for adequate supply in sender wallet
    require((totalDeposited) <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    /// Transfer tokens to contract and get amount sent
    uint amountSent = transferAndCalculate(tokenAddress, totalDeposited);

    /// Create the lock instances
    createLockInstances(tokenAddress, locks, amountSent, totalDeposited);

    emit LockCreated(msg.sender, tokenAddress, uint64(locks.length), nonce);
  }

  /**
   * @notice Create one or multiple lock instances for a single token. Fees are in the form of % of the token deposited.
   * @param tokenAddress Contract address of the erc20 token
   * @param locks array of LockParams struct(s) containing:
   *    ownerAddress The address of the owner wallet
   *    withdrawalAddress The address of the withdrawer
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is a Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @dev Since fees are not paid for in ETH, no ETH is added to the burn meter. This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
   */
  function createLockPercent(address tokenAddress, LockParams[] calldata locks) external {
    /// Calculate total deposit
    uint totalDeposited = calculateTotalDeposited(locks);

    /// Calculate token fee based off total token deposit
    uint tokenFee = MathUpgradeable.mulDiv(totalDeposited, percentLockPrice, 10000);

    /// Check for adequate supply in sender wallet
    require((totalDeposited + tokenFee) <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    /// Transfer tokens to contract and get amount sent
    uint amountSent = transferAndCalculateWithFee(tokenAddress, totalDeposited, tokenFee);

    /// Create the lock instances
    createLockInstances(tokenAddress, locks, amountSent, totalDeposited);

    emit LockCreated(msg.sender, tokenAddress, uint64(locks.length), nonce);
  }

  /**
   * @notice Create one or multiple lock instances for a single token. Fees are in ETH.
   * @param tokenAddress Contract address of the erc20 token
   * @param locks array of LockParams struct(s) containing:
   *    ownerAddress The address of the owner wallet
   *    withdrawalAddress The address of the withdrawer
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is a Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @dev This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
   */
  function createLockEth(address tokenAddress, LockParams[] calldata locks) external payable {
    /// Check for correct message value
    require(msg.value == ethLockPrice * locks.length, "Incorrect price");

    /// Calculate total deposit
    uint totalDeposited = calculateTotalDeposited(locks);

    /// Check for adequate supply in sender wallet
    require(totalDeposited <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    /// Transfer tokens to contract and get amount sent
    uint amountSent = transferAndCalculate(tokenAddress, totalDeposited);

    /// Create the lock instances
    createLockInstances(tokenAddress, locks, amountSent, totalDeposited);

    /// Add to burn amount in ETH burn meter
    handleBurns(msg.value);

    emit LockCreated(msg.sender, tokenAddress, uint64(locks.length), nonce);
  }

  /**
   * @notice Create one or multiple lock instances for a single token using a referral code. Fees are in ETH.
   * @param tokenAddress Contract address of the erc20 token
   * @param locks array of LockParams struct(s) containing:
   *    ownerAddress The address of the owner wallet
   *    withdrawalAddress The address of the withdrawer
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is a Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @param code Referral code used for discount
   * @dev This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
   */
  function createLockWithCodeEth(address tokenAddress, LockParams[] calldata locks, string calldata code) external payable {
    /// Check for referral valid code
    require(referralContract.checkIfActive(code), "Invalid code");

    /// Calculate referral commission
    uint commission = (ethLockPrice * codeDiscount * locks.length) / 100;

    /// Check for correct message value
    require(msg.value == (ethLockPrice * locks.length - commission), "Incorrect price");

    /// Calculate total deposit
    uint totalDeposited = calculateTotalDeposited(locks);

    /// Check for adequate supply in sender wallet
    require(totalDeposited <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    /// Transfer tokens to contract and get amount sent
    uint amountSent = transferAndCalculate(tokenAddress, totalDeposited);

    /// Create the lock instances
    createLockInstances(tokenAddress, locks, amountSent, totalDeposited);

    /// Add to burn amount burn meter
    handleBurns(msg.value);

    /// Distribute commission
    distributeCommission(code, commission);

    emit LockCreated(msg.sender, tokenAddress, uint64(locks.length), nonce);
  }

  /**
   * @notice Claim specified number of unlocked tokens. Will delete the lock if all tokens are withdrawn.
   * @param _nonce lock instance id of the targeted lock
   * @param amount Amount of tokens attempting to be withdrawn
   */
  function withdrawUnlockedTokens(uint64 _nonce, uint amount) external {
    /// Check if the amount attempting to be withdrawn is valid
    require(amount <= getClaimableTokens(_nonce), "Withdraw balance");
    /// Revert 0 withdraw
    require(amount > 0, "Withdrawn min");
    /// Check that sender is the withdrawal address
    require(lockInstance[_nonce].withdrawalAddress == msg.sender, "Withdraw Ownership");

    /// Decrement amount current by the amount being withdrawn
    lockInstance[_nonce].currentAmount -= amount;

    /// Transfer tokens from the contract to the recipient
    transferTokensTo(lockInstance[_nonce].tokenAddress, msg.sender, amount);

    /// Delete lock instance if current amount reaches zero
    if (lockInstance[_nonce].currentAmount <= 0) deleteLockInstance(_nonce);

    emit TokensWithdrawn(msg.sender, amount, _nonce);
  }

  /**
   * @notice Transfer ownership of lock instance, only callable by lock owner
   * @param _nonce ID of desired lock instance
   * @param _address Address of new owner address
   */
  function transferLockOwnership(uint64 _nonce, address _address) external {
    require(_address != address(0), "Zero address");
    /// Check that sender is the lock owner
    require(lockInstance[_nonce].ownerAddress == msg.sender, "Ownership");
    /// Revert same transfer
    require(_address != msg.sender, "Same transfer");

    /// Delete mapping from the old owner to nonce of lock instance and pop
    uint64[] storage ownerArray = ownerToLock[msg.sender];
    for (uint64 i = 0; i < ownerArray.length; i++) {
      if (ownerArray[i] == _nonce) {
        ownerArray[i] = ownerArray[ownerArray.length - 1];
        ownerArray.pop();
        break;
      }
    }

    /// Change lock owner in lock instance to new owner
    lockInstance[_nonce].ownerAddress == _address;

    /// Map nonce of transferred lock to the new owner
    ownerToLock[_address].push(_nonce);

    emit LockTransferred(msg.sender, _address, _nonce);
  }

  /**
   * @notice Transfer withdrawal address of lock instance, only callable by lock owner
   * @param _nonce ID of desired lock instance
   * @param _address Address of new withdrawal address
   */
  function setLockWithdrawalAddress(uint64 _nonce, address _address) external {
    require(_address != address(0), "Zero address");
    /// Check that sender is the lock owner
    require(lockInstance[_nonce].ownerAddress == msg.sender, "Ownership");
    /// Revert same transfer
    require(_address != lockInstance[_nonce].withdrawalAddress, "Same transfer");

    /// Delete mapping from the old owner to nonce of lock instance and pop
    uint64[] storage withdrawArray = withdrawalToLock[msg.sender];
    for (uint64 i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _nonce) {
        withdrawArray[i] = withdrawArray[withdrawArray.length - 1];
        withdrawArray.pop();
        break;
      }
    }

    /// Change lock owner in lock instance to new owner
    lockInstance[_nonce].withdrawalAddress == _address;

    /// Map nonce of transferred lock to the new owner
    withdrawalToLock[_address].push(_nonce);

    emit WithdrawalTransferred(msg.sender, _address, _nonce);
  }

  /**
   * @notice Relock or add tokens to an existing lock. If not whitelisted. fees are in ETH. Start date for standard locks are immutable.
   * @param _nonce lock instance id of the targeted lock
   * @param amount amount of tokens to relock, if any
   * @param startTime time in seconds to add to the existing start date
   * @param endTime time in seconds to add to the existing end date
   */
  function relockETH(uint64 _nonce, uint amount, uint64 startTime, uint64 endTime) external payable {
    address tokenAddress = lockInstance[_nonce].tokenAddress;

    /// Check if token is whitelisted
    if (whitelistContract.getIsWhitelisted(tokenAddress)) {
      /// Check if msg value is 0
      require(msg.value == 0, "Incorrect Price");
    } else {
      /// Check if msg value is correct
      require(msg.value == ethRelockPrice, "Incorrect Price");
    }

    /// Check that sender is the lock owner
    require(lockInstance[_nonce].ownerAddress == msg.sender, "Ownership");

    /// Check if sender has adequate token blance if sender is adding tokens to the lock
    if (amount > 0) require(IERC20Upgradeable(tokenAddress).balanceOf(msg.sender) >= amount, "Token balance");
    /// Standard lock start dates cannot be modified
    if (lockInstance[_nonce].startDate == 0) require(startTime == 0, "Start date");
    /// Check for end date upper bounds
    require(endTime + lockInstance[_nonce].endDate < 10000000000, "End date");

    if (amount > 0) {
      /// Transfer tokens to contract and get amount sent
      uint amountSent = transferAndCalculate(tokenAddress, amount);
      lockInstance[_nonce].currentAmount += amountSent;
      lockInstance[_nonce].depositAmount += amountSent;
    }

    if (startTime > 0) lockInstance[_nonce].startDate += startTime;
    if (endTime > 0) lockInstance[_nonce].endDate += endTime;

    /// Add to burn amount burn meter
    handleBurns(msg.value);

    emit LockRelocked(msg.sender, amount, startTime, endTime, _nonce);
  }

  /**
   * @notice Relock or add tokens to an existing lock. If not whitelisted, fees are in % of tokens in the lock. Start date for standard locks immutable.
   * @param _nonce lock instance id of the targeted lock
   * @param amount amount of tokens to relock, if any
   * @param startTime time in seconds to add to the existing start date
   * @param endTime time in seconds to add to the existing end date
   */
  function relockPercent(uint64 _nonce, uint amount, uint64 startTime, uint64 endTime) external {
    address tokenAddress = lockInstance[_nonce].tokenAddress;

    /// Check that sender is the lock owner
    require(lockInstance[_nonce].ownerAddress == msg.sender, "Ownership");

    /// Check if sender has adequate token blance if sender is adding tokens to the lock
    if (amount > 0) require(IERC20Upgradeable(tokenAddress).balanceOf(msg.sender) >= amount, "Token balance");
    /// Standard lock start dates cannot be modified
    if (lockInstance[_nonce].startDate == 0) require(startTime == 0, "Start date");

    /// Check for end date upper bounds
    require(endTime + lockInstance[_nonce].endDate < 10000000000, "End date");

    if (amount > 0) {
      /// Transfer tokens to contract and get amount sent
      uint amountSent = transferAndCalculate(tokenAddress, amount);
      lockInstance[_nonce].currentAmount += amountSent;
      lockInstance[_nonce].depositAmount += amountSent;
    }

    if (startTime > 0) lockInstance[_nonce].startDate += startTime;
    if (endTime > 0) lockInstance[_nonce].endDate += endTime;

    /// Check if token is not whitelisted
    if (!whitelistContract.getIsWhitelisted(tokenAddress)) {
      /// Calculate the token fee based on total tokens in lock
      uint tokenFee = MathUpgradeable.mulDiv(lockInstance[_nonce].currentAmount, percentRelockPrice, 10000);

      /// Deduct fee from token balance
      lockInstance[_nonce].currentAmount -= tokenFee;
      lockInstance[_nonce].depositAmount -= tokenFee;

      /// Transfer token fees to the collector address
      transferTokensTo(tokenAddress, feeCollector, tokenFee);
    }

    emit LockRelocked(msg.sender, amount, startTime, endTime, _nonce);
  }

  /**
   * @notice Split a current lock into two separate locks amount determined by the sender. If not whitelisted, fees are in eth. This function supports both linear and standard locks.
   * @param to address of split receiver
   * @param _nonce ID of desired lock instance
   * @param amount number of tokens sent to new lock
   */
  function splitLockETH(address to, address withdrawalAddress, uint64 _nonce, uint amount) external payable {
    uint currentAmount = lockInstance[_nonce].currentAmount;
    uint depositAmount = lockInstance[_nonce].depositAmount;
    address tokenAddress = lockInstance[_nonce].tokenAddress;

    /// Check if token is whitelisted
    if (whitelistContract.getIsWhitelisted(tokenAddress)) {
      /// Check if msg value is 0
      require(msg.value == 0, "Incorrect Price");
    } else {
      /// Check if msg value is correct
      require(msg.value == ethSplitPrice, "Incorrect Price");
    }

    /// Check that sender is the lock owner
    require(lockInstance[_nonce].ownerAddress == msg.sender, "Onwership");
    /// Check that amount is less than the current amount in the lock
    require(currentAmount > amount, "Balance");
    /// Check that amount is not 0
    require(amount > 0, "Zero transfer");

    /// To maintain linear lock integrity, the deposit amount must maintain proportional to the current amount

    /// Convert amount to corresponding deposit amount and subtract from lock initial deposit
    lockInstance[_nonce].depositAmount -= MathUpgradeable.mulDiv(depositAmount, amount, currentAmount);
    /// Subtract amount from the current amount
    lockInstance[_nonce].currentAmount -= amount;

    nonce++;

    /// Create a new lock instance and map to nonce
    lockInstance[nonce] = LockInstance(tokenAddress, to, withdrawalAddress, amount, MathUpgradeable.mulDiv(depositAmount, amount, currentAmount), lockInstance[_nonce].startDate, lockInstance[_nonce].endDate);
    /// Map token address to nonce
    tokenToLock[tokenAddress].push(nonce);
    /// Map owner address to nonce
    ownerToLock[to].push(nonce);
    /// Map withdrawal address to nonce
    withdrawalToLock[withdrawalAddress].push(nonce);

    /// Add to burn amount burn meter
    handleBurns(msg.value);

    emit LockSplit(msg.sender, to, amount, _nonce, nonce);
  }

  /**
   * @notice This function splits a current lock into two separate locks amount determined by the sender. If not whitelisted, fees are in % of tokens in the lock. This function supports both linear and standard locks.
   * @param to address of split receiver
   * @param _nonce ID of desired lock instance
   * @param amount number of tokens sent to new lock
   * @dev tokens are deducted from the original lock
   */
  function splitLockPercent(address to, address withdrawalAddress, uint64 _nonce, uint amount) external {
    uint currentAmount = lockInstance[_nonce].currentAmount;
    uint depositAmount = lockInstance[_nonce].depositAmount;
    address tokenAddress = lockInstance[_nonce].tokenAddress;

    /// Check that sender is the lock owner
    require(lockInstance[_nonce].ownerAddress == msg.sender, "Ownership");
    /// Check that amount is less than the current amount in the lock
    require(currentAmount > amount, "Balance");
    /// Check that amount is not 0
    require(amount > 0, "Zero transfer");

    /// Check if token is not whitelisted
    if (!whitelistContract.getIsWhitelisted(tokenAddress)) {
      /// Calculate the token fee based on total tokens locked
      uint tokenFee = MathUpgradeable.mulDiv(currentAmount, percentRelockPrice, 10000);
      /// Deduct fee from token balance
      lockInstance[_nonce].currentAmount -= tokenFee;
      lockInstance[_nonce].depositAmount -= tokenFee;
      /// Transfer token fees to the collector address
      transferTokensTo(tokenAddress, feeCollector, tokenFee);
    }

    /// To maintain linear lock integrity, the deposit amount must maintain proportional to the current amount

    /// Convert amount to corresponding deposit amount and subtract from lock initial deposit
    lockInstance[_nonce].depositAmount -= MathUpgradeable.mulDiv(depositAmount, amount, currentAmount);
    /// Subtract amount from the current amount
    lockInstance[_nonce].currentAmount -= amount;

    nonce++;

    /// Create a new lock instance and map to nonce
    lockInstance[nonce] = LockInstance(tokenAddress, to, withdrawalAddress, amount, MathUpgradeable.mulDiv(depositAmount, amount, currentAmount), lockInstance[_nonce].startDate, lockInstance[_nonce].endDate);
    /// Map token address to nonce
    tokenToLock[tokenAddress].push(nonce);
    /// Map owner address to nonce
    ownerToLock[to].push(nonce);
    /// Map withdrawal address to nonce
    withdrawalToLock[withdrawalAddress].push(nonce);

    emit LockSplit(msg.sender, to, amount, _nonce, nonce);
  }

  /**
   * @notice Claim ETH in the contract. Owner only function.
   * @dev Excludes eth in the burn meter.
   */
  function claimETH() external onlyOwner {
    require(burnMeter <= address(this).balance, "Negative widthdraw");
    uint amount = address(this).balance - burnMeter;
    (bool sent, ) = payable(msg.sender).call{ value: amount }("");
    require(sent, "Failed to send Ether");
  }

  /**
   * @notice Set the fee collection address. Owner only function.
   * @param _feeCollector Address of the fee collector
   */
  function setFeeCollector(address _feeCollector) external onlyOwner {
    require(_feeCollector != address(0), "Zero Address");
    feeCollector = _feeCollector;
  }

  /**
   * @notice Set the Uniswap router address. Owner only function.
   * @param _routerAddress Address of uniswap router
   */
  function setRouter(address _routerAddress) external onlyOwner {
    require(_routerAddress != address(0), "Zero Address");
    routerContract = IDEXRouter(_routerAddress);
  }

  /**
   * @notice Set the referral contract address. Owner only function.
   * @param _referralAddress Address of Moon Labs referral address
   */
  function setReferralContract(address _referralAddress) external onlyOwner {
    require(_referralAddress != address(0), "Zero Address");
    referralContract = IMoonLabsReferral(_referralAddress);
  }

  /**
   * @notice Set the burn threshold in WEI. Owner only function.
   * @param _burnThreshold Amount of ETH in WEI
   */
  function setBurnThreshold(uint _burnThreshold) external onlyOwner {
    burnThreshold = _burnThreshold;
  }

  /**
   * @notice Set the price for a single lock instance in WEI. Owner only function.
   * @param _ethLockPrice Amount of ETH in WEI
   */
  function setLockPrice(uint _ethLockPrice) external onlyOwner {
    ethLockPrice = _ethLockPrice;
  }

  /**
   * @notice Set the price splitting a lock in WEI. Owner only function.
   * @param _ethSplitPrice Amount of ETH in WEI
   */
  function setSplitPrice(uint _ethSplitPrice) external onlyOwner {
    ethSplitPrice = _ethSplitPrice;
  }

  /**
   * @notice Set the price for relocking a lock in WEI. Owner only function.
   * @param _ethRelockPrice Amount of ETH in WEI
   */
  function setRelockPrice(uint _ethRelockPrice) external onlyOwner {
    ethRelockPrice = _ethRelockPrice;
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
   * @notice Set the Moon Labs native token address. Owner only function.
   * @param _tokenToBurn Valid ERC20 address
   */
  function setTokenToBurn(address _tokenToBurn) external onlyOwner {
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
  }

  /**
   * @notice Set percentage of ETH per lock sent to the burn meter. Owner only function.
   * @param _burnPercent Percentage represented in 10s
   */
  function setBurnPercent(uint8 _burnPercent) external onlyOwner {
    require(_burnPercent <= 100, "Max percent");
    burnPercent = _burnPercent;
  }

  /**
   * @notice Set the percent of deposited tokens taken for a lock that is paid for using tokens. Owner only function.
   * @param _percentLockPrice Percentage represented in 10000s
   */
  function setPercentLockPrice(uint16 _percentLockPrice) external onlyOwner {
    require(_percentLockPrice <= 10000, "Max percent");
    percentLockPrice = _percentLockPrice;
  }

  /**
   * @notice Set the percent of deposited tokens taken for a split that is paid for using tokens. Owner only function.
   * @param _percentSplitPrice Percentage represented in 10000s
   */
  function setPercentSplitPrice(uint16 _percentSplitPrice) external onlyOwner {
    require(_percentSplitPrice <= 10000, "Max percent");
    percentSplitPrice = _percentSplitPrice;
  }

  /**
   * @notice Set the percent of deposited tokens taken for a relock that is paid for using tokens. Owner only function.
   * @param _percentRelockPrice Percentage represented in 10000s
   */
  function setPercentRelockPrice(uint16 _percentRelockPrice) external onlyOwner {
    require(_percentRelockPrice <= 10000, "Max percent");
    percentRelockPrice = _percentRelockPrice;
  }

  /**
   * @notice Retrieve an array of lock IDs tied to a single owner address
   * @param ownerAddress address of desired lock owner
   * @return Array of lock instance IDs
   */
  function getNonceFromOwnerAddress(address ownerAddress) external view returns (uint64[] memory) {
    return ownerToLock[ownerAddress];
  }

  /**
   * @notice Retrieve an array of lock IDs tied to a single withdrawal address
   * @param withdrawalAddress address of desired withdraw owner
   * @return Array of lock instance IDs
   */
  function getNonceFromWithdrawalAddress(address withdrawalAddress) external view returns (uint64[] memory) {
    return withdrawalToLock[withdrawalAddress];
  }

  /**
   * @notice Retrieve an array of lock IDs tied to a single token address
   * @param tokenAddress token address of desired ERC20 token
   * @return Array of lock instance IDs
   */
  function getNonceFromTokenAddress(address tokenAddress) external view returns (uint64[] memory) {
    return tokenToLock[tokenAddress];
  }

  /**
   * @notice Retrieve information of a single lock instance
   * @param _nonce ID of desired lock instance
   * @return token address, owner address, withdrawal address, deposit amount, current amount, start date, end date
   */
  function getLock(uint64 _nonce) external view returns (address, address, address, uint, uint, uint64, uint64) {
    return (lockInstance[_nonce].tokenAddress, lockInstance[_nonce].ownerAddress, lockInstance[_nonce].withdrawalAddress, lockInstance[_nonce].depositAmount, lockInstance[_nonce].currentAmount, lockInstance[_nonce].startDate, lockInstance[_nonce].endDate);
  }

  /*|| === PUBLIC FUNCTIONS === ||*/
  /**
   * @notice Retrieve unlocked tokens for a lock instance
   * @param _nonce ID of desired lock instance
   * @return Number of unlocked tokens
   */
  function getClaimableTokens(uint64 _nonce) public view returns (uint) {
    uint currentAmount = lockInstance[_nonce].currentAmount;
    uint64 endDate = lockInstance[_nonce].endDate;
    uint64 startDate = lockInstance[_nonce].startDate;

    /// Check if the token balance is 0
    if (currentAmount <= 0) return 0;

    /// Check if the lock is a standard lock
    if (startDate == 0) return endDate <= block.timestamp ? currentAmount : 0;

    /// If none of the above then the token is a linear lock
    return calculateLinearWithdraw(_nonce);
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  /**
   * @notice Create single or multiple lock instances, maps nonce to lock instance, token address to nonce, owner address to nonce. Checks for valid
   * start date, end date, and deposit amount.
   * @param tokenAddress ID of desired lock instance
   * @param amountSent actual amount of tokens sent to the smart contract
   * @param totalDeposited hypothetical amount of tokens sent to the smart contract
   * @param locks array of LockParams struct(s) containing:
   *    ownerAddress The address of the owner wallet
   *    withdrawalAddress The address of the withdrawer
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is a Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   */
  function createLockInstances(address tokenAddress, LockParams[] calldata locks, uint amountSent, uint totalDeposited) private {
    for (uint64 i = 0; i < locks.length; i++) {
      uint depositAmount = locks[i].depositAmount;
      uint64 startDate = locks[i].startDate;
      uint64 endDate = locks[i].endDate;
      require(startDate < endDate, "Start date");
      require(endDate < 10000000000, "End date");
      require(locks[i].depositAmount > 0, "Min deposit");

      /// Create a new Lock Instance and map to nonce
      lockInstance[nonce] = LockInstance(tokenAddress, locks[i].ownerAddress, locks[i].withdrawalAddress, MathUpgradeable.mulDiv(amountSent, depositAmount, totalDeposited), MathUpgradeable.mulDiv(amountSent, depositAmount, totalDeposited), startDate, endDate);
      /// Map token address to nonce
      tokenToLock[tokenAddress].push(nonce);
      /// Map owner address to nonce
      ownerToLock[locks[i].ownerAddress].push(nonce);
      /// Map withdrawal address to nonce
      withdrawalToLock[locks[i].withdrawalAddress].push(nonce);
    }
  }

  /**
   * @notice claculates total deposit of given lock array
   * @param lock array of LockParams struct(s) containing:
   *    withdrawalAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the vesting instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @return total deposit amount
   */
  function calculateTotalDeposited(LockParams[] memory lock) private pure returns (uint) {
    uint totalDeposited;
    for (uint32 i = 0; i < lock.length; i++) {
      totalDeposited += lock[i].depositAmount;
    }
    return totalDeposited;
  }

  /**
   * @notice transfers tokens to contract and calcualtes amount sent
   * @param tokenAddress address of the token
   * @param totalDeposited total tokens attempting to be sent
   * @return total amount sent
   */
  function transferAndCalculate(address tokenAddress, uint totalDeposited) private returns (uint) {
    /// Get balance before sending tokens
    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));

    /// Transfer tokens from sender to contract
    transferTokensFrom(tokenAddress, msg.sender, totalDeposited);

    /// Calculate amount sent based off before and after balance
    return IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;
  }

  /**
   * @notice transfers tokens to contract and calcualtes amount sent with fees
   * @param tokenAddress address of the token
   * @param totalDeposited total tokens attempting to be sent
   * @param tokenFee fee taken for locking
   * @return total amount sent
   */
  function transferAndCalculateWithFee(address tokenAddress, uint totalDeposited, uint tokenFee) private returns (uint) {
    /// Get balance before sending tokens
    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));

    /// Transfer tokens from sender to contract
    transferTokensFrom(tokenAddress, msg.sender, totalDeposited + tokenFee);

    /// Transfer token fees to the collector address
    transferTokensTo(tokenAddress, feeCollector, tokenFee);

    /// Calculate amount sent based off before and after balance
    return IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;
  }

  /**
   * @dev Transfer tokens from address to this contract. Used for abstraction and readability.
   * @param tokenAddress token address of ERC20 to be transferred
   * @param from the address of the wallet transferring the token
   * @param amount number of tokens being transferred
   */
  function transferTokensFrom(address tokenAddress, address from, uint amount) private {
    IERC20Upgradeable(tokenAddress).safeTransferFrom(from, address(this), amount);
  }

  /**
   * @dev Transfer tokens from this contract to an address. Used for abstraction and readability.
   * @param tokenAddress token address of ERC20 to be transferred
   * @param to address of wallet receiving the token
   * @param amount number of tokens being transferred
   */
  function transferTokensTo(address tokenAddress, address to, uint amount) private {
    IERC20Upgradeable(tokenAddress).safeTransfer(to, amount);
  }

  /**
   * @notice Buy Moon Labs native token if burn threshold is met or crossed and send to the dead address
   */
  function handleBurns(uint value) private {
    burnMeter += (value * burnPercent) / 100;
    /// Check if the threshold is met
    uint _burnMeter = burnMeter;
    if (burnMeter >= burnThreshold) {
      /// Buy tokenToBurn via Uniswap router and send to the dead address
      address[] memory path = new address[](2);
      path[0] = routerContract.WETH();
      path[1] = address(tokenToBurn);
      routerContract.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: _burnMeter }(0, path, 0x000000000000000000000000000000000000dEaD, block.timestamp);
      _burnMeter = 0;
      burnMeter = _burnMeter;
    }
  }

  /**
   * @notice Distribute ETH to the owner of the referral code
   * @param code referral code
   * @param commission amount of eth to send to referral code owner
   */
  function distributeCommission(string memory code, uint commission) private nonReentrant {
    /// Get referral code owner
    address payable to = payable(referralContract.getAddressByCode(code));
    /// Send ether to code owner
    (bool sent, ) = to.call{ value: commission }("");
    if (sent) {
      /// Log rewards in the referral contract
      referralContract.addRewardsEarned(code, commission);
    }
  }

  /**
   * @notice Delete a lock instance and the mappings belonging to it.
   * @param _nonce ID of desired lock instance
   */
  function deleteLockInstance(uint64 _nonce) private {
    /// Delete mapping from the lock owner to nonce of lock instance and pop
    uint64[] storage ownerArray = ownerToLock[lockInstance[_nonce].ownerAddress];
    for (uint64 i = 0; i < ownerArray.length; i++) {
      if (ownerArray[i] == _nonce) {
        ownerArray[i] = ownerArray[ownerArray.length - 1];
        ownerArray.pop();
        break;
      }
    }

    /// Delete mapping from the withdrawal address to nonce of lock instance and pop
    uint64[] storage withdrawArray = withdrawalToLock[lockInstance[_nonce].withdrawalAddress];
    for (uint64 i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _nonce) {
        withdrawArray[i] = withdrawArray[withdrawArray.length - 1];
        withdrawArray.pop();
        break;
      }
    }

    /// Delete mapping from the token address to nonce of the lock instance and pop
    uint64[] storage tokenAddress = tokenToLock[lockInstance[_nonce].tokenAddress];
    for (uint64 i = 0; i < tokenAddress.length; i++) {
      if (tokenAddress[i] == _nonce) {
        tokenAddress[i] = tokenAddress[tokenAddress.length - 1];
        tokenAddress.pop();
        break;
      }
    }
    /// Delete lock instance map
    delete lockInstance[_nonce];
  }

  /**
   * @notice Calculate the number of unlocked tokens within a linear lock.
   * @param _nonce ID of desired lock instance
   * @return unlockedTokens number of unlocked tokens
   */
  function calculateLinearWithdraw(uint64 _nonce) private view returns (uint) {
    uint currentAmount = lockInstance[_nonce].currentAmount;
    uint depositAmount = lockInstance[_nonce].depositAmount;
    uint64 endDate = lockInstance[_nonce].endDate;
    uint64 startDate = lockInstance[_nonce].startDate;
    uint64 timeBlock = endDate - startDate; /// Time from start date to end date
    uint64 timeElapsed = 0; /// Time since tokens started to unlock

    if (endDate <= block.timestamp) {
      /// Set time elapsed to time block
      timeElapsed = timeBlock;
    } else if (startDate < block.timestamp) {
      /// Set time elapsed to the time elapsed
      timeElapsed = uint64(block.timestamp) - startDate;
    }

    /// Math to calculate linear unlock
    /**
    This formula will only return a negative number when the current amount is less than what can be withdrawn

      Deposit Amount x Time Elapsed
      -----------------------------   -   (Deposit Amount - Current Amount)
               Time Block
    **/
    return MathUpgradeable.mulDiv(depositAmount, timeElapsed, timeBlock) - (depositAmount - currentAmount);
  }
}
