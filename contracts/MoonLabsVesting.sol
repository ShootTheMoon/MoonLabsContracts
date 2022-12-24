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

  function initialize(address _tokenToBurn, uint32 _burnPercent, uint32 _percentLockPrice, uint _ethLockPrice, address _feeCollector, address _referralAddress, address _routerAddress) public initializer {
    __Ownable_init();
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
    burnPercent = _burnPercent;
    percentLockPrice = _percentLockPrice;
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
  uint64 public index; // Lock identifier
  uint32 public burnPercent;
  uint32 public percentLockPrice; // Percent per eth paid lock, represented at 10x the percent
  IERC20Upgradeable public tokenToBurn;
  IDEXRouter public routerContract;
  IMoonLabsReferral public referralContract;

  /*|| === STRUCTS VARIABLES === ||*/
  struct VestingInstance {
    address tokenAddress; // Address of locked token
    uint totalSupply; // Total supply of token, used for accomodating rebase tokens
    address creatorAddress; // Lock creator
    address withdrawAddress; // Withdraw address
    uint depositAmount; // Initial deposit amount
    uint currentAmount; // Current tokens in lock
    uint64 startDate; // Linear lock if !=0. Date when tokens start to unlock
    uint64 endDate; // Date when tokens are fully unlocked
  }

  struct LockParams {
    address withdrawAddress; // Withdraw address
    uint depositAmount; // Initial deposit amount
    uint64 startDate; // Linear lock if !=0. Date when tokens start to unlock
    uint64 endDate; // Date when tokens are fully unlocked
  }

  struct TokenInfo {
    uint totalSupply;
    uint64[] tokenLocks;
  }

  /*|| === MAPPINGS === ||*/
  mapping(address => uint64[]) private withdrawToLock; // Map all locks to withdraw address
  mapping(address => TokenInfo) private tokenInfo; // Map all locks to token struct
  mapping(uint64 => VestingInstance) private vestingInstance;

  /*|| === MODIFIERS === ||*/
  modifier withdrawOwner(uint64 _index) {
    require(msg.sender == vestingInstance[_index].withdrawAddress, "You do not own this lock");
    _;
  }

  /*|| === EVENTS === ||*/
  event LockCreated(address indexed creator, address indexed token, uint indexed numOfLocks);
  event TokensWithdrawn(address indexed from, address indexed token, uint64 index);
  event LockTransfered(address indexed from, address indexed to, uint64 index);
  event LockDeleted(address indexed withdrawAddress, address indexed token, uint64 index);

  /*|| === PUBLIC FUNCTIONS === ||*/
  // Return claimable tokens
  function getClaimableTokens(uint64 _index) public view returns (uint) {
    uint _currentAmount = vestingInstance[_index].currentAmount;
    uint64 _endDate = vestingInstance[_index].endDate;
    uint64 _startDate = vestingInstance[_index].startDate;

    // Check if the token balance is 0
    if (_currentAmount == 0) {
      return 0;
    }

    // Check if lock is a normal lock
    if (_startDate == 0) {
      return _endDate <= block.timestamp ? _currentAmount : 0;
    }

    // If none of the above then the token is a linear lock
    return calculateLinearWithdraw(_index);
  }

  // Transfer withdraw address
  function transferVestingOwnership(uint64 _index, address _newOwner) public nonReentrant withdrawOwner(_index) {
    // Change withdraw owner in vesting instance to new owner
    vestingInstance[_index].withdrawAddress = _newOwner;

    // Delete mapping from old owner to index of vesting instance and pop
    uint64[] storage _withdrawArray = withdrawToLock[msg.sender];
    for (uint64 i = 0; i < _withdrawArray.length; i++) {
      if (_withdrawArray[i] == _index) {
        for (uint64 j = i; j < _withdrawArray.length - 1; j++) {
          _withdrawArray[j] = _withdrawArray[j + 1];
        }
        _withdrawArray.pop();
      }
    }
    // Map index of transferred lock to new owner
    withdrawToLock[_newOwner].push(_index);
    emit LockTransfered(msg.sender, _newOwner, _index);
  }

  /*|| === EXTERNAL FUNCTIONS === ||*/

  // Create vesting instance(s) paid for in token percentage
  function createLockPercent(address _tokenAddress, LockParams[] calldata l) external {
    IERC20Upgradeable _token = IERC20Upgradeable(_tokenAddress);
    uint _totalSupply = _token.totalSupply();
    uint _totalDepositAmount;
    for (uint64 i; i < l.length; i++) {
      _totalDepositAmount += l[i].depositAmount;
      createVestingInstance(_tokenAddress, _totalSupply, l[i]);
    }

    uint _tokenFee = (_totalDepositAmount * percentLockPrice) / 1000;

    transferTokensFrom(_tokenAddress, msg.sender, _totalDepositAmount);
    _token.safeTransferFrom(msg.sender, address(this), _totalDepositAmount);

    // Transfer token fees to collector address
    transferTokensTo(_tokenAddress, feeCollector, _tokenFee);

    // Emit lock created event
    emit LockCreated(msg.sender, _tokenAddress, l.length);
  }

  // Create vesting instance(s) paid for in eth
  function createLockEth(address _tokenAddress, LockParams[] calldata l) external payable {
    // Check if msg value is correct
    require(msg.value == ethLockPrice * l.length, "Incorrect price");

    IERC20Upgradeable _token = IERC20Upgradeable(_tokenAddress);
    uint _totalSupply = _token.totalSupply();
    uint _totalDepositAmount;
    for (uint64 i; i < l.length; i++) {
      _totalDepositAmount += l[i].depositAmount;
      createVestingInstance(_tokenAddress, _totalSupply, l[i]);
    }

    transferTokensFrom(_tokenAddress, msg.sender, _totalDepositAmount);
    _token.safeTransferFrom(msg.sender, address(this), _totalDepositAmount);

    // Add to burn amount burn meter
    burnMeter += (msg.value * burnPercent) / 100;

    handleBurns();

    // Emit lock created event
    emit LockCreated(msg.sender, _tokenAddress, l.length);
  }

  // Create vesting instance(s) with referral code
  function createLockWithCodeEth(address _tokenAddress, LockParams[] calldata l, string memory _code) external payable {
    // Check for referral valid code
    require(referralContract.checkIfActive(_code) == true, "Invalid code");
    // Calculate discount
    uint _discount = (((ethLockPrice * codeDiscount) / 100) * l.length);
    // Calcuate commission
    uint _commission = (((ethLockPrice * codeCommission) / 100) * l.length);
    // Check if msg value is correct
    require(msg.value == (ethLockPrice * l.length - _discount), "Incorrect price");
    // Distribute commission
    distributeCommission(_code, _commission);

    IERC20Upgradeable _token = IERC20Upgradeable(_tokenAddress);
    uint _totalSupply = _token.totalSupply();
    uint _totalDepositAmount;
    for (uint64 i; i < l.length; i++) {
      _totalDepositAmount += l[i].depositAmount;
      createVestingInstance(_tokenAddress, _totalSupply, l[i]);
    }

    transferTokensFrom(_tokenAddress, msg.sender, _totalDepositAmount);
    _token.safeTransferFrom(msg.sender, address(this), _totalDepositAmount);

    // Add to burn amount burn meter
    burnMeter += (msg.value * burnPercent) / 100;

    handleBurns();

    // Emit lock created event
    emit LockCreated(msg.sender, _tokenAddress, l.length);
  }

  // Claim unlocked tokens
  function withdrawUnlockedTokens(uint64 _index, uint _amount) external withdrawOwner(_index) {
    require(_amount <= getClaimableTokens(_index), "Exceeds withdraw balance");
    require(_amount > 0, "Cannot withdraw 0 tokens");
    address _address = vestingInstance[_index].tokenAddress;

    // Subtract amount withdrawn from current amount
    vestingInstance[_index].currentAmount -= _amount;
    // Transfer tokens from contract to recipient
    transferTokensTo(vestingInstance[_index].tokenAddress, msg.sender, _amount);

    // Delete vesting instance if no tokens are left
    if (vestingInstance[_index].currentAmount == 0) {
      deleteVestingInstance(_index);
    }
    // Emits TokensWithdrawn event
    emit TokensWithdrawn(msg.sender, _address, _index);
  }

  // Claim ETH in contract
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
  function getVestingIndexFromWithdrawAddress(address _withdrawAddress) external view returns (uint64[] memory) {
    return withdrawToLock[_withdrawAddress];
  }

  // Return vest index from token address
  function getVestingIndexFromTokenAddress(address _tokenAddress) external view returns (uint64[] memory) {
    return tokenInfo[_tokenAddress].tokenLocks;
  }

  // Return vesting instance from index
  function getVestingInstance(uint64 _index) external view returns (VestingInstance memory) {
    return vestingInstance[_index];
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  // Create vesting instance
  function createVestingInstance(address _tokenAddress, uint _totalSupply, LockParams calldata l) private {
    require(l.depositAmount > 0, "Deposit amount must be greater than 0");
    require(l.startDate < l.endDate, "Start date must come before end date");
    require(l.endDate < 10000000000, "Invalid end date");

    // Increment index
    index++;

    // Create new VestingInstance struct and add to index
    vestingInstance[index] = VestingInstance(_tokenAddress, _totalSupply, msg.sender, l.withdrawAddress, l.depositAmount, l.depositAmount, l.startDate, l.endDate);

    // Create map to withdraw address
    withdrawToLock[l.withdrawAddress].push(index);

    // Create map to token address
    tokenInfo[_tokenAddress].tokenLocks.push(index);
  }

  // Transfer tokens to contract
  function transferTokensFrom(address _tokenAddress, address _sender, uint _amount) private {
    IERC20Upgradeable(_tokenAddress).safeTransferFrom(_sender, address(this), _amount);
  }

  // Transfer tokens to address
  function transferTokensTo(address _tokenAddress, address _reciever, uint _amount) private {
    // Transfer tokens to contract
    IERC20Upgradeable(_tokenAddress).safeTransfer(_reciever, _amount);
  }

  // Delete vesting instance
  function deleteVestingInstance(uint64 _index) private {
    address withdrawAddress = vestingInstance[_index].withdrawAddress;
    address tokenAddress = vestingInstance[_index].tokenAddress;

    // Delete vesting instance map
    delete vestingInstance[_index];

    // Emit deletion event
    emit LockDeleted(withdrawAddress, tokenAddress, _index);
  }

  // Get the current amount of unlocked tokens
  function calculateLinearWithdraw(uint64 _index) private view returns (uint unlockedTokens) {
    uint64 _endDate = vestingInstance[_index].endDate;
    uint64 _startDate = vestingInstance[_index].startDate;
    uint _currentAmount = vestingInstance[_index].currentAmount;
    uint _depositAmount = vestingInstance[_index].depositAmount;
    uint64 _timeBlock = _endDate - _startDate; // Time from start date to end date
    uint64 _timeElapsed;

    if (_endDate <= block.timestamp) {
      _timeBlock = _timeElapsed;
    } else if (_startDate < block.timestamp) {
      _timeElapsed = uint64(block.timestamp) - _startDate;
    }

    // Math to calculate linear unlock
    /*
    This formula will only return a negative number when the current amount is less than what can actually be withdrawn

      Deposit Amount x Time Elapsed
      -----------------------------   -   (Deposit Amount - Current Amount)
               Time Block
    */
    return MathUpgradeable.mulDiv(_depositAmount, _timeBlock, _timeElapsed) - (_depositAmount - _currentAmount);
  }

  // Distribute commission
  function distributeCommission(string memory _code, uint _value) private {
    address payable to = payable(referralContract.getAddressByCode(_code));
    to.transfer(_value);
    referralContract.addRewardsEarned(_code, _value);
  }

  function handleBurns() private {
    // Check if threshold is met
    if (burnMeter >= burnThreshold) {
      // Buy tokenToBurn via uniswap router and send to dead address
      address[] memory _path = new address[](2);
      _path[0] = routerContract.WETH();
      _path[1] = address(tokenToBurn);
      routerContract.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: burnMeter }(0, _path, 0x000000000000000000000000000000000000dEaD, block.timestamp);
      burnMeter = 0;
    }
  }
}
