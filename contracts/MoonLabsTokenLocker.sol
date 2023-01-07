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
 * @title A token locker contract for ERC20 tokens.
 * @author Moon Labs LLC
 * @notice This contract's intended purpose is to allow users to create token locks for ERC20 tokens. Lock creators may extend, transfer, add to, and
 * split locks. Lock creators may NOT unlock tokens prematurely for whatever reason. Tokens locked in this contract remain locked until their
 * respective unlock date without ANY exceptions. To maximize gas efficiency, this contract is not suited to handle rebasing tokens or tokens in
 * which a wallets supply changes based on total supply.
 */

pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./IDEXRouter.sol";

interface IMoonLabsReferral {
  function checkIfActive(string calldata code) external view returns (bool);

  function getAddressByCode(string memory code) external view returns (address);

  function addRewardsEarned(string calldata code, uint commission) external;
}

interface IMoonLabsWhitelist {
  function getIsWhitelisted(address _address) external view returns (bool);
}

contract MoonLabsTokenLocker is ReentrancyGuardUpgradeable, OwnableUpgradeable {
  function initialize(address _tokenToBurn, uint32 _burnPercent, uint32 _percentLockPrice, uint _ethLockPrice, address _feeCollector, address referralAddress, address whitelistAddress, address routerAddress, uint32 _codeDiscount, uint32 _codeCommission, uint _burnThreshold) public initializer {
    __Ownable_init();
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
    burnPercent = _burnPercent;
    percentLockPrice = _percentLockPrice;
    ethLockPrice = _ethLockPrice;
    feeCollector = _feeCollector;
    referralContract = IMoonLabsReferral(referralAddress);
    whitelistContract = IMoonLabsWhitelist(whitelistAddress);
    routerContract = IDEXRouter(routerAddress);
    codeDiscount = _codeDiscount;
    codeCommission = _codeCommission;
    burnThreshold = _burnThreshold;
  }

  /*|| === STATE VARIABLES === ||*/
  uint public ethLockPrice; /// Price in WEI for each lock instance when paying for lock with ETH
  uint public burnThreshold; /// ETH in WEI when tokenToBurn should be bought and sent to DEAD address
  uint public burnMeter; /// Current ETH in WEI for buying and burning tokenToBurn
  address public feeCollector; /// Fee collection address for paying with token percent
  uint64 public nonce; /// Unique lock identifier
  uint32 public codeDiscount; /// Discount in the percentage applied to the customer when using referral code, represented in 10s
  uint32 public codeCommission; /// Percentage of each lock purchase sent to referral code owner, represented in 10s
  uint32 public burnPercent; /// Percent of each transaction sent to burnMeter, represented in 10s
  uint32 public percentLockPrice; /// Percent of deposited tokens taken for a lock that is paid for using tokens, represented in 10000s
  IERC20Upgradeable public tokenToBurn; /// Native Moon Labs token
  IDEXRouter public routerContract; /// Uniswap router
  IMoonLabsReferral public referralContract; /// Moon Labs referral contract
  IMoonLabsWhitelist public whitelistContract; /// Moon Labs whitelist contract

  /*|| === STRUCTS VARIABLES === ||*/
  struct LockInstance {
    address tokenAddress; /// Address of locked token
    uint depositAmount; /// Total deposit amount
    uint withdrawnAmount; /// Total withdrawn amount
    uint64 startDate; /// Date when tokens start to unlock, is Linear lock if !=0.
    uint64 endDate; /// Date when all tokens are fully unlocked
  }

  struct LockParams {
    uint depositAmount;
    uint64 startDate;
    uint64 endDate;
    address ownerAddress;
  }

  /*|| === MAPPINGS === ||*/
  mapping(address => uint64[]) private ownerToLock; /// Owner address to array of locks
  mapping(address => uint64[]) private tokenToLock; /// Token address to array of locks
  mapping(uint64 => LockInstance) private lockInstance; /// Nonce to lock

  /*|| === EVENTS === ||*/
  event LockCreated(address indexed creator, address indexed token, uint indexed numOfLocks);
  event TokensWithdrawn(address indexed from, address indexed token, uint32 indexed nonce);
  event LockTransfered(address indexed from, address indexed to, uint32 indexed nonce);

  /*|| === EXTERNAL FUNCTIONS === ||*/
  /**  
    @notice Create one or multiple lock instances for a single token for whitelisted tokens.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    ownerAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
    @dev Since this lock is free, no ETH is added to the burn meter. This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
  */
  function createLockWhitelist(address tokenAddress, LockParams[] calldata lock) external {
    /// Check if token is whitelisted
    require(whitelistContract.getIsWhitelisted(tokenAddress), "Token is not whitelisted");
    /// Calculate total deposit
    uint totalDeposit;
    for (uint32 i; i < lock.length; i++) {
      totalDeposit += lock[i].depositAmount;
    }

    /// Check for adequate supply in sender wallet
    require((totalDeposit) <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    /// Transfer tokens from sender to contract
    transferTokensFrom(tokenAddress, msg.sender, totalDeposit);
    uint amountSent = IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;

    uint64 _nonce = nonce;
    /// Create a lock instance for every struct in the lock array
    for (uint64 i = 0; i < lock.length; i++) {
      _nonce++;
      createLockInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
    }

    nonce = _nonce;

    /// Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  /**
   * @notice Create one or multiple lock instances for a single token. Fees are in the form of % of the token deposited.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    ownerAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @dev Since fees are not paid for in ETH, no ETH is added to the burn meter. This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
   */
  function createLockPercent(address tokenAddress, LockParams[] calldata lock) external {
    /// Calculate total deposit
    uint totalDeposit;
    for (uint32 i; i < lock.length; i++) {
      totalDeposit += lock[i].depositAmount;
    }

    /// Calculate token fee based off total token deposit
    uint tokenFee = MathUpgradeable.mulDiv(totalDeposit, percentLockPrice, 10000);
    /// Check for adequate supply in sender wallet
    require((totalDeposit + tokenFee) <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    /// Transfer tokens from sender to contract
    transferTokensFrom(tokenAddress, msg.sender, totalDeposit + tokenFee);
    uint amountSent = IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;

    uint64 _nonce = nonce;
    /// Create a lock instance for every struct in the lock array
    for (uint64 i = 0; i < lock.length; i++) {
      _nonce++;
      createLockInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
    }

    nonce = _nonce;

    /// Transfer token fees to the collector address
    transferTokensTo(tokenAddress, feeCollector, tokenFee);

    /// Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  /**
   * @notice Create one or multiple lock instances for a single token. Fees are in ETH.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    ownerAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @dev This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
   */
  function createLockEth(address tokenAddress, LockParams[] calldata lock) external payable {
    /// Check for correct message value
    require(msg.value == ethLockPrice * lock.length, "Incorrect price");
    /// Calculate total deposit
    uint totalDeposit;
    for (uint32 i; i < lock.length; i++) {
      totalDeposit += lock[i].depositAmount;
    }
    /// Check for adequate supply in sender wallet
    require(totalDeposit <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    /// Transfer tokens from sender to contract
    transferTokensFrom(tokenAddress, msg.sender, totalDeposit);
    uint amountSent = IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;

    uint64 _nonce = nonce;
    /// Create a lock instance for every struct in the lock array
    for (uint64 i; i < lock.length; i++) {
      _nonce++;
      createLockInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
    }

    nonce = _nonce;

    /// Add to burn amount in ETH burn meter
    burnMeter += (msg.value * burnPercent) / 100;

    handleBurns();

    /// Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  /**
   * @notice Create one or multiple lock instances for a single token using a referral code. Fees are in ETH.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    ownerAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @param code Referral code used for discount
   * @dev This function supports tokens with a transfer tax, although not recommended due to potential customer confusion
   */
  function createLockWithCodeEth(address tokenAddress, LockParams[] calldata lock, string calldata code) external payable {
    uint _ethLockPrice = ethLockPrice;
    /// Check for referral valid code
    require(referralContract.checkIfActive(code), "Invalid code");
    /// Check for correct message value
    require(msg.value == (_ethLockPrice * lock.length - (((_ethLockPrice * codeDiscount) / 100) * lock.length)), "Incorrect price");
    /// Calculate total deposit
    uint totalDeposit;
    for (uint32 i; i < lock.length; i++) {
      totalDeposit += lock[i].depositAmount;
    }
    /// Check for adequate supply in sender wallet
    require(totalDeposit <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Token balance");

    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    /// Transfer tokens from sender to contract
    transferTokensFrom(tokenAddress, msg.sender, totalDeposit);
    uint amountSent = IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;

    uint64 _nonce = nonce;
    /// Create a lock instance for every struct in the lock array
    for (uint64 i = 0; i < lock.length; i++) {
      _nonce++;
      createLockInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
    }

    nonce = _nonce;

    /// Add to burn amount burn meter
    burnMeter += (msg.value * burnPercent) / 100;

    handleBurns();

    /// Distribute commission
    distributeCommission(code, (((_ethLockPrice * codeCommission) / 100) * lock.length));

    /// Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  /*|| === PUBLIC FUNCTIONS === ||*/
  /**
   * @notice Transfer withdraw ownership of vesting instance, only callable by withdraw owner
   * @param _nonce ID of desired vesting instance
   * @param newOwner Address of new withdraw address
   */
  function transferVestingOwnership(uint32 _nonce, address newOwner) public nonReentrant {
    /// Check that caller is the withdraw owner of the lock
    require(_nonce == ownerToLock[msg.sender], "Ownership");
    /// Delete mapping from the old owner to nonce of vesting instance and pop
    uint64[] storage withdrawArray = ownerToLock[msg.sender];
    for (uint64 i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _nonce) {
        withdrawArray[i] = withdrawArray[withdrawArray.length - 1];
        withdrawArray.pop();
        break;
      }
    }

    /// Map nonce of transferred lock to the new owner
    ownerToLock[newOwner].push(_nonce);
    /// Emit lock transferred event
    emit LockTransfered(msg.sender, newOwner, _nonce);
  }

  /**
   * @notice Retrieve unlocked tokens for a lock instance
   * @param _nonce ID of desired lock instance
   * @return Number of unlocked tokens
   */
  function getClaimableTokens(uint32 _nonce) public view returns (uint) {
    uint withdrawnAmount = lockInstance[_nonce].withdrawnAmount;
    uint depositAmount = lockInstance[_nonce].depositAmount;
    uint64 endDate = lockInstance[_nonce].endDate;
    uint64 startDate = lockInstance[_nonce].startDate;

    // Check if the token balance is 0
    if (withdrawnAmount >= depositAmount) return 0;

    // Check if the lock is a normal lock
    if (startDate == 0) return endDate <= block.timestamp ? depositAmount - withdrawnAmount : 0;

    // If none of the above then the token is a linear lock
    return calculateLinearWithdraw(_nonce);
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  /**
   * @notice Create a single lock instance, maps nonce to lock instance, token address to nonce, owner address to nonce. Checks for valid
   * start date, end date, and deposit amount.
   * @param tokenAddress ID of desired lock instance
   * @param lock array of LockParams struct(s) containing:
   *    ownerAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the lock instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   */
  function createLockInstance(address tokenAddress, LockParams calldata lock, uint64 _nonce, uint amountSent, uint totalDeposit) private {
    uint depositAmount = lock.depositAmount;
    uint64 startDate = lock.startDate;
    uint64 endDate = lock.endDate;
    require(startDate < endDate, "Start date");
    require(endDate < 10000000000, "End date");
    require(lock.depositAmount > 0, "Min deposit");

    /// Create a new Lock Instance and map to nonce
    lockInstance[_nonce] = LockInstance(tokenAddress, MathUpgradeable.mulDiv(amountSent, depositAmount, totalDeposit), 0, startDate, endDate);
    /// Map token address to nonce
    tokenToLock[tokenAddress].push(_nonce);
    /// Map owner address to nonce
    ownerToLock[lock.ownerAddress].push(_nonce);
  }

  /**
   * @dev Transfer tokens from address to this contract. Used for abstraction and readability.
   * @param tokenAddress token address of ERC20 to be transferred
   * @param from the address of wallet transferring the token
   * @param amount number of tokens being transferred
   */
  function transferTokensFrom(address tokenAddress, address from, uint amount) private {
    IERC20Upgradeable(tokenAddress).transferFrom(from, address(this), amount);
  }

  /**
   * @dev Transfer tokens from this contract to an address. Used for abstraction and readability.
   * @param tokenAddress token address of ERC20 to be transferred
   * @param to address of wallet receiving the token
   * @param amount number of tokens being transferred
   */
  function transferTokensTo(address tokenAddress, address to, uint amount) private {
    IERC20Upgradeable(tokenAddress).transfer(to, amount);
  }

  /**
   * @notice Buy Moon Labs native token if burn threshold is met or crossed and send to the dead address
   */
  function handleBurns() private {
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
  function distributeCommission(string memory code, uint commission) private {
    /// Get referral code owner
    address payable to = payable(referralContract.getAddressByCode(code));
    to.transfer(commission);
    /// Log rewards in the referral contract
    referralContract.addRewardsEarned(code, commission);
  }

  /**
   * @notice Delete a lock instance and the mappings belonging to it.
   * @param _nonce ID of desired lock instance
   */
  function deleteLockInstance(uint32 _nonce) private {
    /// Delete mapping from the withdraw owner to nonce of lock instance and pop
    uint64[] storage ownerArray = ownerToLock[msg.sender];
    for (uint64 i = 0; i < ownerArray.length; i++) {
      if (ownerArray[i] == _nonce) {
        ownerArray[i] = ownerArray[ownerArray.length - 1];
        ownerArray.pop();
        break;
      }
    }

    /// Delete mapping from the token address to nonce of lock instance and pop
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
    uint withdrawnAmount = lockInstance[_nonce].withdrawnAmount;
    uint depositAmount = lockInstance[_nonce].depositAmount;
    uint64 endDate = lockInstance[_nonce].endDate;
    uint64 startDate = lockInstance[_nonce].startDate;
    uint64 timeBlock = endDate - startDate; /// Time from start date to end date
    uint64 timeElapsed; // Time since tokens started to unlock

    if (endDate <= block.timestamp) {
      /// Set time elapsed to time block
      timeElapsed = timeBlock;
    } else if (startDate < block.timestamp) {
      /// Set time elapsed to the time elapse
      timeElapsed = uint64(block.timestamp) - startDate;
    }

    /// Math to calculate linear unlock
    /**
    This formula will only return a negative number when the current amount is less than what can be withdrawn

      Deposit Amount x Time Elapsed
      -----------------------------   -   (Withdrawn Amount)
               Time Block
    **/
    return MathUpgradeable.mulDiv(depositAmount, timeElapsed, timeBlock) - (withdrawnAmount);
  }
}
