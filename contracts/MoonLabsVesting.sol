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
 * @title A token vesting contract for NON-Rebasing ERC20 tokens
 * @author Moon Labs LLC
 * @notice This contract's intended purpose is for token owners to create token locks for future or current holders that are immutable by the lock
 * creator. There are no premature unlock conditions or lock extensions. To maximize gas efficiency, this contract is not suited to handle rebasing
 * tokens or tokens in which a wallets supply changes based on total supply.
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

contract MoonLabsVesting is ReentrancyGuardUpgradeable, OwnableUpgradeable {
  function initialize(address _tokenToBurn, uint32 _burnPercent, uint32 _percentLockPrice, uint _ethLockPrice, address _feeCollector, address referralAddress, address whitelistAddress, address routerAddress) public initializer {
    __Ownable_init();
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
    burnPercent = _burnPercent;
    percentLockPrice = _percentLockPrice;
    ethLockPrice = _ethLockPrice;
    feeCollector = _feeCollector;
    referralContract = IMoonLabsReferral(referralAddress);
    whitelistContract = IMoonLabsWhitelist(whitelistAddress);
    routerContract = IDEXRouter(routerAddress);
    codeDiscount = 10;
    codeCommission = 10;
    burnThreshold = 250000000000000000;
  }

  /*|| === STATE VARIABLES === ||*/
  uint public ethLockPrice; /// Price in WEI for each vesting instance when paying for lock with ETH
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
  struct VestingInstance {
    address tokenAddress; /// Address of locked token
    address withdrawAddress; /// Withdraw address
    uint depositAmount; /// Total deposit amount
    uint withdrawnAmount; /// Total withdrawn amount
    uint64 startDate; /// Date when tokens start to unlock, is Linear lock if !=0.
    uint64 endDate; /// Date when all tokens are fully unlocked
  }

  struct LockParams {
    address withdrawAddress;
    uint depositAmount;
    uint64 startDate;
    uint64 endDate;
  }

  /*|| === MAPPINGS === ||*/
  mapping(address => uint64[]) private withdrawToLock; /// Withdraw address to array of locks
  mapping(address => uint64[]) private tokenToLock; /// Token address to array of locks
  mapping(uint64 => VestingInstance) private vestingInstance; /// Nonce to vesting instance

  /*|| === EVENTS === ||*/
  event LockCreated(address indexed creator, address indexed token, uint indexed numOfLocks);
  event TokensWithdrawn(address indexed from, address indexed token, uint32 indexed nonce);
  event LockTransfered(address indexed from, address indexed to, uint32 indexed nonce);

  /*|| === EXTERNAL FUNCTIONS === ||*/
  /**  
    @notice Create one or multiple vesting instances for a single token for whitelisted tokens.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    withdrawAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the vesting instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
    @dev Since this lock is free, no ETH is added to the burn meter. Although not recommended due to potential customer confusion, this function supports tokens with a transfer tax.
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
    /// Create a vesting instance for every struct in the lock array
    for (uint64 i = 0; i < lock.length; i++) {
      _nonce++;
      createVestingInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
    }

    nonce = _nonce;

    /// Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  /**
   * @notice Create one or multiple vesting instances for a single token. Fees are in the form of % of the token deposited.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    withdrawAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the vesting instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @dev Since fees are not paid for in ETH, no ETH is added to the burn meter. Although not recommended due to potential customer confusion,
   * function supports tokens with a transfer tax.
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
    /// Create a vesting instance for every struct in the lock array
    for (uint64 i = 0; i < lock.length; i++) {
      _nonce++;
      createVestingInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
    }

    nonce = _nonce;

    /// Transfer token fees to the collector address
    transferTokensTo(tokenAddress, feeCollector, tokenFee);

    /// Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  /**
   * @notice Create one or multiple vesting instances for a single token. Fees are in ETH.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    withdrawAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the vesting instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @dev Although not recommended due to potential customer confusion, this function supports tokens with a transfer tax.
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
    /// Create a vesting instance for every struct in the lock array
    for (uint64 i; i < lock.length; i++) {
      _nonce++;
      createVestingInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
    }

    nonce = _nonce;

    /// Add to burn amount in ETH burn meter
    burnMeter += (msg.value * burnPercent) / 100;

    handleBurns();

    /// Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  /**
   * @notice Create one or multiple vesting instances for a single token using a referral code. Fees are in ETH.
   * @param tokenAddress Contract address of the erc20 token
   * @param lock array of LockParams struct(s) containing:
   *    withdrawAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the vesting instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   * @param code Referral code used for discount
   * @dev Although not recommended due to potential customer confusion, this function supports tokens with a transfer tax.
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
    /// Create a vesting instance for every struct in the lock array
    for (uint64 i = 0; i < lock.length; i++) {
      _nonce++;
      createVestingInstance(tokenAddress, lock[i], _nonce, amountSent, totalDeposit);
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

  /**
   * @notice Claim specified number of unlocked tokens. Will delete the lock if all tokens are withdrawn.
   * @param _nonce Vesting instance id of the targeted lock
   * @param amount Amount of tokens attempting to be withdrawn
   */
  function withdrawUnlockedTokens(uint32 _nonce, uint amount) external {
    /// Check if the amount attempting to be withdrawn is valid
    require(amount <= getClaimableTokens(_nonce), "Withdraw balance");
    require(amount > 0, "Withdrawn min");
    /// Check that caller is the withdraw owner of the lock
    require(msg.sender == vestingInstance[_nonce].withdrawAddress, "Ownership");
    address tokenAddress = vestingInstance[_nonce].tokenAddress;

    /// Increment amount withdrawn by the amount being withdrawn
    vestingInstance[_nonce].withdrawnAmount += amount;
    /// Transfer tokens from the contract to the recipient
    transferTokensTo(vestingInstance[_nonce].tokenAddress, msg.sender, amount);

    /// Delete vesting instance if no tokens are left
    if (vestingInstance[_nonce].withdrawnAmount >= vestingInstance[_nonce].depositAmount) {
      deleteVestingInstance(_nonce);
    }
    /// Emits TokensWithdrawn event
    emit TokensWithdrawn(msg.sender, tokenAddress, _nonce);
  }

  /**
   * @notice Claim ETH in contract. Owner only function.
   * @dev Excludes eth in the burn meter.
   */
  function claimETH() external onlyOwner {
    require(burnMeter <= address(this).balance, "Cannot withdraw negative eth");
    address payable to = payable(msg.sender);
    uint amount = address(this).balance - burnMeter;
    to.transfer(amount);
  }

  /**
   * @notice Set the fee collection address. Owner only function.
   */
  function setFeeCollector(address _feeCollector) external onlyOwner {
    feeCollector = _feeCollector;
  }

  /**
   * @notice Set the Uniswap router address. Owner only function.
   * @param _routerAddress Address of uniswap router
   */
  function setRouter(address _routerAddress) external onlyOwner {
    routerContract = IDEXRouter(_routerAddress);
  }

  /**
   * @notice Set the referral contract address. Owner only function.
   * @param _referralAddress Address of Moon Labs referral address
   */
  function setReferralContract(address _referralAddress) external onlyOwner {
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
   * @notice Set the price for a single vesting instance in WEI. Owner only function.
   * @param _ethLockPrice Amount of ETH in WEI
   */
  function setLockPrice(uint _ethLockPrice) external onlyOwner {
    ethLockPrice = _ethLockPrice;
  }

  /**
   * @notice Set the percentage of ETH per lock discounted on code use. Owner only function.
   * @param _codeDiscount Percentage represented in 10s
   */
  function setCodeDiscount(uint32 _codeDiscount) external onlyOwner {
    codeDiscount = _codeDiscount;
  }

  /**
   * @notice Set the percentage of ETH per lock distributed to code owner. Owner only function.
   * @param _codeCommission Percentage represented in 10s
   */
  function setCodeCommission(uint32 _codeCommission) external onlyOwner {
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
  function setBurnPercent(uint32 _burnPercent) external onlyOwner {
    require(_burnPercent <= 100, "Max percent");
    burnPercent = _burnPercent;
  }

  /**
   * @notice Set the percent of deposited tokens taken for a lock that is paid for using tokens. Owner only function.
   * @param _percentLockPrice Percentage represented in 10000s
   */
  function setPercentLockPrice(uint32 _percentLockPrice) external onlyOwner {
    require(_percentLockPrice <= 10000, "Max percent");
    percentLockPrice = _percentLockPrice;
  }

  /**
   * @notice Retrieve an array of vesting IDs tied to a single withdraw wallet address
   * @param withdrawAddress Wallet address of desired withdraw wallet
   * @return Array of vesting instance IDs
   */
  function getNonceFromWithdrawAddress(address withdrawAddress) external view returns (uint64[] memory) {
    return withdrawToLock[withdrawAddress];
  }

  /**
   * @notice Retrieve an array of vesting IDs tied to a single token address
   * @param tokenAddress token address of desired ERC20 token
   * @return Array of vesting instance IDs
   */
  function getNonceFromTokenAddress(address tokenAddress) external view returns (uint64[] memory) {
    return tokenToLock[tokenAddress];
  }

  /**
   * @notice Retrieve information of a single vesting instance
   * @param _nonce ID of desired vesting instance
   * @return token address, withdraw address, deposit amount, withdrawn amount, start date, end date
   */
  function getInstance(uint32 _nonce) external view returns (address, address, uint, uint, uint64, uint64) {
    return (vestingInstance[_nonce].tokenAddress, vestingInstance[_nonce].withdrawAddress, vestingInstance[_nonce].depositAmount, vestingInstance[_nonce].withdrawnAmount, vestingInstance[_nonce].startDate, vestingInstance[_nonce].endDate);
  }

  /*|| === PUBLIC FUNCTIONS === ||*/
  /**
   * @notice Transfer withdraw ownership of vesting instance, only callable by withdraw owner
   * @param _nonce ID of desired vesting instance
   * @param newOwner Address of new withdraw address
   */
  function transferVestingOwnership(uint32 _nonce, address newOwner) public nonReentrant {
    /// Check that caller is the withdraw owner of the lock
    require(msg.sender == vestingInstance[_nonce].withdrawAddress, "Ownership");
    /// Delete mapping from the old owner to nonce of vesting instance and pop
    uint64[] storage withdrawArray = withdrawToLock[msg.sender];
    for (uint64 i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _nonce) {
        withdrawArray[i] = withdrawArray[withdrawArray.length - 1];
        withdrawArray.pop();
        break;
      }
    }

    /// Change withdraw owner in vesting instance to the new owner
    vestingInstance[_nonce].withdrawAddress = newOwner;

    /// Map nonce of transferred lock to the new owner
    withdrawToLock[newOwner].push(_nonce);
    /// Emit lock transferred event
    emit LockTransfered(msg.sender, newOwner, _nonce);
  }

  /**
   * @notice Retrieve unlocked tokens for a vesting instance
   * @param _nonce ID of desired vesting instance
   * @return Number of unlocked tokens
   */
  function getClaimableTokens(uint32 _nonce) public view returns (uint) {
    uint withdrawnAmount = vestingInstance[_nonce].withdrawnAmount;
    uint depositAmount = vestingInstance[_nonce].depositAmount;
    uint64 endDate = vestingInstance[_nonce].endDate;
    uint64 startDate = vestingInstance[_nonce].startDate;

    // Check if the token balance is 0
    if (withdrawnAmount >= depositAmount) return 0;

    // Check if the lock is a normal lock
    if (startDate == 0) return endDate <= block.timestamp ? depositAmount - withdrawnAmount : 0;

    // If none of the above then the token is a linear lock
    return calculateLinearWithdraw(_nonce);
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  /**
   * @notice Create a single vesting instance, maps nonce to vesting instance, token address to nonce, withdraw address to nonce. Checks for valid
   * start date, end date, and deposit amount.
   * @param tokenAddress ID of desired vesting instance
   * @param lock array of LockParams struct(s) containing:
   *    withdrawAddress The address of the receiving wallet
   *    depositAmount Number of tokens in the vesting instance
   *    startDate Date when tokens start to unlock, is Linear lock if !=0.
   *    endDate Date when all tokens are fully unlocked
   */
  function createVestingInstance(address tokenAddress, LockParams calldata lock, uint64 _nonce, uint amountSent, uint totalDeposit) private {
    uint depositAmount = lock.depositAmount;
    address withdrawAddress = lock.withdrawAddress;
    uint64 startDate = lock.startDate;
    uint64 endDate = lock.endDate;
    require(startDate < endDate, "Start date");
    require(endDate < 10000000000, "End date");
    require(lock.depositAmount > 0, "Min deposit");

    /// Create a new Vesting Instance and map to nonce
    vestingInstance[_nonce] = VestingInstance(tokenAddress, withdrawAddress, MathUpgradeable.mulDiv(amountSent, depositAmount, totalDeposit), 0, startDate, endDate);
    /// Map token address to nonce
    tokenToLock[tokenAddress].push(_nonce);
    /// Map withdraw address to nonce
    withdrawToLock[withdrawAddress].push(_nonce);
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
   * @notice Delete a vesting instance and the mappings belonging to it.
   * @param _nonce ID of desired vesting instance
   */
  function deleteVestingInstance(uint32 _nonce) private {
    /// Delete mapping from the withdraw owner to nonce of vesting instance and pop
    uint64[] storage withdrawArray = withdrawToLock[msg.sender];
    for (uint64 i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _nonce) {
        withdrawArray[i] = withdrawArray[withdrawArray.length - 1];
        withdrawArray.pop();
        break;
      }
    }

    /// Delete mapping from the token address to nonce of vesting instance and pop
    uint64[] storage tokenAddress = tokenToLock[vestingInstance[_nonce].tokenAddress];
    for (uint64 i = 0; i < tokenAddress.length; i++) {
      if (tokenAddress[i] == _nonce) {
        tokenAddress[i] = tokenAddress[tokenAddress.length - 1];
        tokenAddress.pop();
        break;
      }
    }
    /// Delete vesting instance map
    delete vestingInstance[_nonce];
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
   * @notice Calculate the number of unlocked tokens within a linear lock.
   * @param _nonce ID of desired vesting instance
   * @return unlockedTokens number of unlocked tokens
   */
  function calculateLinearWithdraw(uint64 _nonce) private view returns (uint) {
    uint withdrawnAmount = vestingInstance[_nonce].withdrawnAmount;
    uint depositAmount = vestingInstance[_nonce].depositAmount;
    uint64 endDate = vestingInstance[_nonce].endDate;
    uint64 startDate = vestingInstance[_nonce].startDate;
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
