// SPDX-License-Identifier: UNLICENSED

// ███╗   ███╗ ██████╗  ██████╗ ███╗   ██╗    ██╗      █████╗ ██████╗ ███████╗
// ████╗ ████║██╔═══██╗██╔═══██╗████╗  ██║    ██║     ██╔══██╗██╔══██╗██╔════╝
// ██╔████╔██║██║   ██║██║   ██║██╔██╗ ██║    ██║     ███████║██████╔╝███████╗
// ██║╚██╔╝██║██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══██║██╔══██╗╚════██║
// ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║ ╚████║    ███████╗██║  ██║██████╔╝███████║
// ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝
// Moon Labs LLC reserves all rights on this code.
// You may not, except otherwise with prior permission and express written consent by Moon Labs LLC, copy, download, print, extract, exploit,
// adapt, edit, modify, republish, reproduce, rebroadcast, duplicate, distribute, or publicly display any of the content, information, or material
// on this smart contract for non-personal or commercial purposes, except for any other use as permitted by the applicable copyright law.
//
// This is for ERC20 tokens and should NOT be used for Uniswap LP tokens or ANY other token protocol.
//
// Website: https://www.moonlabs.site/

pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./IDEXRouter.sol";

interface IMoonLabsReferral {
  function checkIfActive(string calldata _code) external view returns (bool);

  function getAddressByCode(string memory _code) external view returns (address);

  function addRewardsEarned(string calldata _code, uint _value) external;
}

contract MoonLabsVesting is ReentrancyGuardUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  function initialize(address _tokenToBurn, uint8 _burnPercent, uint8 _percentLockPrice, uint _ethLockPrice, address _feeCollector, address _referralAddress, address _routerAddress) public initializer {
    __Ownable_init();
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
    burnPercent = _burnPercent;
    percentLockPrice = 25;
    ethLockPrice = _ethLockPrice;
    feeCollector = _feeCollector;
    referralContract = IMoonLabsReferral(_referralAddress);
    routerContract = IDEXRouter(_routerAddress);
    codeDiscount = 10;
    codeCommission = 10;
    burnThreshold = 250000000000000000;
  }

  /*|| === STATE VARIABLES === ||*/
  uint public ethLockPrice; // Price per eth paid lock
  uint public codeDiscount; // Discount in percentage applied to customer
  uint public codeCommission; // Percentage sent to code owner
  uint public burnThreshold; // Threshold in wei
  uint public burnMeter;
  address public feeCollector; // Fee collection address
  uint32 public index; // Lock identifier
  uint32 public burnPercent;
  uint32 public percentLockPrice; // Percent per eth paid lock, represented at 10x the percent
  IERC20Upgradeable public tokenToBurn;
  IDEXRouter public routerContract;
  IMoonLabsReferral public referralContract;

  /*|| === STRUCTS VARIABLES === ||*/
  struct VestingInstance {
    address tokenAddress; // Address of locked token
    address withdrawAddress; // Withdraw address
    uint depositAmount; // Initial deposit amount based on supply of when lock was created
    uint withdrawnAmount; // Total withdrawn amount based on supply of when lock was created
    uint64 startDate; // Linear lock if !=0. Date when tokens start to unlock
    uint64 endDate; // Date when tokens are fully unlocked
  }

  struct LockParams {
    address withdrawAddress; // Withdraw address
    uint depositAmount; // Initial deposit amount
    uint64 startDate; // Linear lock if !=0. Date when tokens start to unlock
    uint64 endDate; // Date when tokens are fully unlocked
  }

  /*|| === MAPPINGS === ||*/
  mapping(address => uint32[]) private withdrawToLock;
  mapping(address => uint32[]) private tokenToLock;
  mapping(uint32 => VestingInstance) private vestingInstance;

  /*|| === MODIFIERS === ||*/
  modifier withdrawOwner(uint32 _index) {
    require(msg.sender == vestingInstance[_index].withdrawAddress, "You do not own this lock");
    _;
  }

  /*|| === EVENTS === ||*/
  event LockCreated(address indexed creator, address indexed token, uint indexed numOfLocks);
  event TokensWithdrawn(address indexed from, address indexed token, uint64 index);
  event LockTransfered(address indexed from, address indexed to, uint64 index);
  event LockDeleted(address indexed withdrawAddress, address indexed token, uint64 index);

  /*|| === EXTERNAL FUNCTIONS === ||*/
  // Create vesting instance(s) paid for in token percentage
  function createLockPercent(address tokenAddress, LockParams[] calldata lock) external {
    uint totalDeposit;
    for (uint32 i; i < lock.length; i++) {
      totalDeposit += lock[i].depositAmount;
    }
    // Calculate token fee
    uint tokenFee = MathUpgradeable.mulDiv(totalDeposit, percentLockPrice, 10000);
    require((totalDeposit + tokenFee) <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Insignificant token balance");

    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    transferTokensFrom(tokenAddress, msg.sender, totalDeposit);
    uint amountSent = IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;

    // Check that correct amount of tokens were sent
    require(amountSent == totalDeposit, "Transfer tax");

    for (uint32 i; i < lock.length; i++) {
      createVestingInstance(tokenAddress, lock[i]);
    }

    // Transfer token fees to collector address
    transferTokensTo(tokenAddress, feeCollector, tokenFee);

    // Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  // Create vesting instance(s) paid for in eth
  function createLockEth(address tokenAddress, LockParams[] calldata lock) external payable {
    // Check if msg value is correct
    require(msg.value == ethLockPrice * lock.length, "Incorrect price");

    uint totalDeposit;
    for (uint64 i; i < lock.length; i++) {
      totalDeposit += lock[i].depositAmount;
    }

    require(totalDeposit <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Insignificant token balance");

    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    transferTokensFrom(tokenAddress, msg.sender, totalDeposit);
    uint amountSent = IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;

    // Check that correct amount of tokens were sent
    require(amountSent == totalDeposit, "Transfer tax");

    for (uint64 i; i < lock.length; i++) {
      createVestingInstance(tokenAddress, lock[i]);
    }

    // Add to burn amount burn meter
    burnMeter += (msg.value * burnPercent) / 100;

    handleBurns();

    // Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  // Create vesting instance(s) with referral code
  function createLockWithCodeEth(address tokenAddress, LockParams[] calldata lock, string calldata code) external payable {
    // Check for referral valid code
    require(referralContract.checkIfActive(code) == true, "Invalid code");
    // Calculate discount
    uint discount = (((ethLockPrice * codeDiscount) / 100) * lock.length);
    // Calcuate commission
    uint commission = (((ethLockPrice * codeCommission) / 100) * lock.length);
    // Check if msg value is correct
    require(msg.value == (ethLockPrice * lock.length - discount), "Incorrect price");

    uint totalDeposit;
    for (uint64 i; i < lock.length; i++) {
      totalDeposit += lock[i].depositAmount;
    }

    require(totalDeposit <= IERC20Upgradeable(tokenAddress).balanceOf(msg.sender), "Insignificant token balance");

    uint previousBal = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
    transferTokensFrom(tokenAddress, msg.sender, totalDeposit);
    uint amountSent = IERC20Upgradeable(tokenAddress).balanceOf(address(this)) - previousBal;

    // Check that correct amount of tokens were sent
    require(amountSent == totalDeposit, "Transfer tax");

    for (uint64 i; i < lock.length; i++) {
      createVestingInstance(tokenAddress, lock[i]);
    }

    // Add to burn amount burn meter
    burnMeter += (msg.value * burnPercent) / 100;

    handleBurns();

    // Distribute commission
    distributeCommission(code, commission);

    // Emit lock created event
    emit LockCreated(msg.sender, tokenAddress, lock.length);
  }

  // Claim unlocked tokens
  function withdrawUnlockedTokens(uint32 _index, uint amount) external withdrawOwner(_index) {
    require(amount <= getClaimableTokens(_index), "Exceeds withdraw balance");
    require(amount > 0, "Cannot withdraw 0 tokens");
    address tokenAddress = vestingInstance[_index].tokenAddress;

    // Subtract amount withdrawn from current amount
    vestingInstance[_index].withdrawnAmount += amount;
    // Transfer tokens from contract to recipient
    transferTokensTo(vestingInstance[_index].tokenAddress, msg.sender, amount);

    // Delete vesting instance if no tokens are left
    if (vestingInstance[_index].withdrawnAmount >= vestingInstance[_index].depositAmount) {
      deleteVestingInstance(_index);
    }
    // Emits TokensWithdrawn event
    emit TokensWithdrawn(msg.sender, tokenAddress, _index);
  }

  // Claim ETH in contract900
  function claimETH() external onlyOwner {
    address payable to = payable(msg.sender);
    to.transfer(address(this).balance);
  }

  // Set fee collector address
  function setFeeCollector(address _feeCollector) external onlyOwner {
    feeCollector = _feeCollector;
  }

  // Set router address
  function setRouter(address _routerAddress) external onlyOwner {
    routerContract = IDEXRouter(_routerAddress);
  }

  // Set referral contract
  function setReferralContract(address _referralAddress) external onlyOwner {
    referralContract = IMoonLabsReferral(_referralAddress);
  }

  // Set burnThreshold in wei
  function setBurnThreshold(uint _burnThreshold) external onlyOwner {
    burnThreshold = _burnThreshold;
  }

  // Set lock price in wei
  function setLockPrice(uint _ethLockPrice) external onlyOwner {
    ethLockPrice = _ethLockPrice;
  }

  // Set referral code discount
  function setCodeDiscount(uint _codeDiscount) external onlyOwner {
    codeDiscount = _codeDiscount;
  }

  // Set referral code commission
  function setCodeCommission(uint _codeCommission) external onlyOwner {
    codeCommission = _codeCommission;
  }

  // Change token to auto burn
  function setTokenToBurn(address _tokenToBurn) external onlyOwner {
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
  }

  // Change amount of tokens to auto burn
  function setBurnPercent(uint32 _burnPercent) external onlyOwner {
    require(_burnPercent <= 100, "Percent cannot exceed 100");
    burnPercent = _burnPercent;
  }

  // Change amount of tokens to auto burn
  function setPercentLockPrice(uint32 _percentLockPrice) external onlyOwner {
    require(_percentLockPrice <= 100, "Percent cannot exceed 100");
    percentLockPrice = _percentLockPrice;
  }

  // Return vesting index from withdraw address
  function getIndexFromWithdrawAddress(address withdrawAddress) external view returns (uint32[] memory) {
    return withdrawToLock[withdrawAddress];
  }

  // // Return vest index from token address
  // function getIndexFromTokenAddress(address tokenAddress) external view returns (uint32[] memory) {
  //   return tokenToLock[tokenAddress];
  // }

  // Return vesting instance from index
  function getInstance(uint32 _index) external view returns (VestingInstance memory) {
    return vestingInstance[_index];
  }

  /*|| === PUBLIC FUNCTIONS === ||*/
  // Return claimable tokens
  function getClaimableTokens(uint32 _index) public view returns (uint) {
    uint withdrawnAmount = vestingInstance[_index].withdrawnAmount;
    uint depositAmount = vestingInstance[_index].depositAmount;
    uint64 endDate = vestingInstance[_index].endDate;
    uint64 startDate = vestingInstance[_index].startDate;

    // Check if the token balance is 0
    if (withdrawnAmount >= depositAmount) {
      return 0;
    }

    // Check if lock is a normal lock
    if (startDate == 0) {
      return endDate <= block.timestamp ? depositAmount - withdrawnAmount : 0;
    }

    // If none of the above then the token is a linear lock
    return calculateLinearWithdraw(_index);
  }

  // Transfer withdraw address
  function transferVestingOwnership(uint32 _index, address newOwner) public nonReentrant withdrawOwner(_index) {
    // Delete mapping from old owner to index of vesting instance and pop
    uint32[] storage _withdrawArray = withdrawToLock[msg.sender];
    for (uint64 i = 0; i < _withdrawArray.length; i++) {
      if (_withdrawArray[i] == _index) {
        for (uint64 j = i; j < _withdrawArray.length - 1; j++) {
          _withdrawArray[j] = _withdrawArray[j + 1];
        }
        _withdrawArray.pop();
      }
    }

    // Change withdraw owner in vesting instance to new owner
    vestingInstance[_index].withdrawAddress = newOwner;

    // Map index of transferred lock to new owner
    withdrawToLock[newOwner].push(_index);
    emit LockTransfered(msg.sender, newOwner, _index);
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  // Create vesting instance
  function createVestingInstance(address tokenAddress, LockParams calldata lock) private {
    require(lock.startDate < lock.endDate, "Invalid start date");
    require(lock.endDate < 10000000000, "Invalid end date");
    require(lock.depositAmount > 0, "Min deposit");

    // Increment index
    index++;

    // Create new VestingInstance struct and add to index
    vestingInstance[index] = VestingInstance(tokenAddress, lock.withdrawAddress, lock.depositAmount, 0, lock.startDate, lock.endDate);

    // Create map to withdraw address
    withdrawToLock[lock.withdrawAddress].push(index);

    // Create map to token address
    tokenToLock[tokenAddress].push(index);
  }

  // Transfer tokens to contract
  function transferTokensFrom(address tokenAddress, address from, uint amount) private {
    IERC20Upgradeable(tokenAddress).safeTransferFrom(from, address(this), amount);
  }

  // Transfer tokens to address
  function transferTokensTo(address tokenAddress, address to, uint amount) private {
    // Transfer tokens to contract
    IERC20Upgradeable(tokenAddress).safeTransfer(to, amount);
  }

  // Delete vesting instance
  function deleteVestingInstance(uint32 _index) private {
    address withdrawAddress = vestingInstance[_index].withdrawAddress;
    address tokenAddress = vestingInstance[_index].tokenAddress;

    // Delete vesting instance map
    delete vestingInstance[_index];

    // Emit deletion event
    emit LockDeleted(withdrawAddress, tokenAddress, _index);
  }

  // Get the current amount of unlocked tokens
  function calculateLinearWithdraw(uint32 _index) private view returns (uint unlockedTokens) {
    uint withdrawnAmount = vestingInstance[_index].withdrawnAmount;
    uint depositAmount = vestingInstance[_index].depositAmount;
    uint64 endDate = vestingInstance[_index].endDate;
    uint64 startDate = vestingInstance[_index].startDate;
    uint64 timeBlock = endDate - startDate; // Time from start date to end date
    uint64 timeElapsed;

    if (endDate <= block.timestamp) {
      timeBlock = timeElapsed;
    } else if (startDate < block.timestamp) {
      timeElapsed = uint64(block.timestamp) - startDate;
    }

    /// Math to calculate linear unlock
    /**
    This formula will only return a negative number when the current amount is less than what can actually be withdrawn

      Deposit Amount x Time Elapsed
      -----------------------------   -   (Withdrawn Amount)
               Time Block
    **/
    return MathUpgradeable.mulDiv(depositAmount, timeBlock, timeElapsed) - (withdrawnAmount);
  }

  // Distribute commission
  function distributeCommission(string memory code, uint commission) private {
    address payable to = payable(referralContract.getAddressByCode(code));
    to.transfer(commission);
    referralContract.addRewardsEarned(code, commission);
  }

  function handleBurns() private {
    // Check if threshold is met
    if (burnMeter >= burnThreshold) {
      // Buy tokenToBurn via uniswap router and send to dead address
      address[] memory path = new address[](2);
      path[0] = routerContract.WETH();
      path[1] = address(tokenToBurn);
      routerContract.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: burnMeter }(0, path, 0x000000000000000000000000000000000000dEaD, block.timestamp);
      burnMeter = 0;
    }
  }
}
