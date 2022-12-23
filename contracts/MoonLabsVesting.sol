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

pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./IDEXRouter.sol";

interface IMoonLabsReferral {
  function checkIfActive(string calldata _code) external view returns (bool);

  function getAddressByCode(string memory _code) external view returns (address);
}

contract MoonLabsVesting is ReentrancyGuardUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  function initialize(address _tokenToBurn, uint8 _burnPercent, uint _lockPrice, address _referralAddress, address _routerAddress) public initializer {
    __Ownable_init();
    TOKEN_TO_BURN = IERC20Upgradeable(_tokenToBurn);
    BURN_PERCENT = _burnPercent;
    LOCK_PRICE = _lockPrice;
    IMOONLABSREFERRAL = IMoonLabsReferral(_referralAddress);
    IDEXROUTER = IDEXRouter(_routerAddress);
    CODE_DISCOUNT = 10;
    CODE_COMMISSION = 10;
  }

  /*|| === STATE VARIABLES === ||*/
  uint64 public INDEX;
  uint8 public BURN_PERCENT;
  uint public LOCK_PRICE;
  uint public CODE_DISCOUNT; // Discount in percentage applied to customer
  uint public CODE_COMMISSION; // Percentage sent to code owner
  IERC20Upgradeable public TOKEN_TO_BURN;
  IDEXRouter public IDEXROUTER;
  IMoonLabsReferral public IMOONLABSREFERRAL;

  /*|| === STRUCTS VARIABLES === ||*/
  struct VestingInstance {
    address tokenAddress; // Address of locked token
    address creatorAddress; // Lock creator
    address withdrawAddress; // Withdraw address
    uint depositAmount; // Initial deposit amount
    uint currentAmount; // Current tokens in lock
    uint64 startDate; // Linear lock if !=0. Date when tokens start to unlock
    uint64 endDate; // Date when tokens are fully unlocked
  }

  /*|| === MAPPINGS === ||*/
  mapping(address => uint64[]) private CREATOR_TO_LOCK;
  mapping(address => uint64[]) private WITHDRAW_TO_LOCK;
  mapping(address => uint64[]) private TOKEN_TO_LOCK;
  mapping(uint64 => VestingInstance) private VESTING_INSTANCE;

  /*|| === MODIFIERS === ||*/
  modifier withdrawOwner(uint64 _index) {
    require(msg.sender == VESTING_INSTANCE[_index].withdrawAddress, "You do not own this lock");
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
    uint currentAmount = VESTING_INSTANCE[_index].currentAmount;
    uint64 endDate = VESTING_INSTANCE[_index].endDate;
    uint64 startDate = VESTING_INSTANCE[_index].startDate;

    // Check if the token balance is 0
    if (currentAmount == 0) {
      return 0;
    }

    // Check if lock is a normal lock
    if (startDate == 0) {
      return endDate <= block.timestamp ? currentAmount : 0;
    }

    // If none of the above then the token is a linear lock
    return calculateLinearWithdraw(_index);
  }

  // Transfer withdraw address
  function transferVestingOwnership(uint64 _index, address _newOwner) public nonReentrant withdrawOwner(_index) {
    // Change withdraw owner in vesting instance to new owner
    VESTING_INSTANCE[_index].withdrawAddress = _newOwner;

    // Delete mapping from old owner to index of vesting instance and pop
    uint64[] storage withdrawArray = WITHDRAW_TO_LOCK[msg.sender];
    for (uint64 i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _index) {
        for (uint64 j = i; j < withdrawArray.length - 1; j++) {
          withdrawArray[j] = withdrawArray[j + 1];
        }
        withdrawArray.pop();
      }
    }
    // Map index of transferred lock to new owner
    WITHDRAW_TO_LOCK[_newOwner].push(_index);
    emit LockTransfered(msg.sender, _newOwner, _index);
  }

  /*|| === EXTERNAL FUNCTIONS === ||*/
  // Create vesting instance(s)
  function createLock(address _tokenAddress, address[] calldata _withdrawAddress, uint64[] calldata _depositAmount, uint64[] calldata _startDate, uint64[] calldata _endDate) external payable nonReentrant {
    // Check if all arrays are same the size
    require(_withdrawAddress.length == _depositAmount.length && _depositAmount.length == _endDate.length && _endDate.length == _startDate.length, "Unequal array lengths");
    // Check if msg value is correct
    require(msg.value == LOCK_PRICE * _withdrawAddress.length, "Incorrect Price");

    uint totalDepositAmount;

    for (uint64 i; i < _withdrawAddress.length; i++) {
      createVestingInstance(_tokenAddress, _withdrawAddress[i], _depositAmount[i], _startDate[i], _endDate[i]);
      totalDepositAmount += _depositAmount[i];
    }

    transferTokens(_tokenAddress, totalDepositAmount, msg.sender); // Move to function to avoid "Stack too deep error"

    // Buy tokenToBurn via uniswap router and send to dead address
    address[] memory path = new address[](2);
    path[0] = IDEXROUTER.WETH();
    path[1] = address(TOKEN_TO_BURN);

    IDEXROUTER.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: (msg.value * BURN_PERCENT) / 100 }(0, path, 0x000000000000000000000000000000000000dEaD, block.timestamp);

    // Emit lock created event
    emit LockCreated(msg.sender, _tokenAddress, _depositAmount.length);
  }

  // Create vesting instance(s) with referral code
  function createLockWithCode(address _tokenAddress, address[] calldata _withdrawAddress, uint64[] calldata _depositAmount, uint64[] calldata _startDate, uint64[] calldata _endDate, string memory _code) external payable nonReentrant {
    // Check if all arrays are same the size
    require(_withdrawAddress.length == _depositAmount.length && _depositAmount.length == _endDate.length && _endDate.length == _startDate.length, "Unequal array lengths");

    // Check for referral valid code
    require(IMOONLABSREFERRAL.checkIfActive(_code) == true, "Invalid code");
    // Calculate discount
    uint discount = (((LOCK_PRICE * CODE_DISCOUNT) / 100) * _withdrawAddress.length);
    // Calcuate commission
    uint commission = (((LOCK_PRICE * CODE_COMMISSION) / 100) * _withdrawAddress.length);
    // Check if msg value is correct
    require(msg.value == (LOCK_PRICE * _withdrawAddress.length - discount), "Incorrect price");
    // Distribute commission
    distributeCommission(_code, commission);

    uint totalDepositAmount;

    for (uint64 i; i < _withdrawAddress.length; i++) {
      createVestingInstance(_tokenAddress, _withdrawAddress[i], _depositAmount[i], _startDate[i], _endDate[i]);
      totalDepositAmount += _depositAmount[i];
    }

    transferTokens(_tokenAddress, totalDepositAmount, msg.sender); // Move to function to avoid "Stack too deep error"

    // Buy tokenToBurn via uniswap router and send to dead address
    address[] memory path = new address[](2);
    path[0] = IDEXROUTER.WETH();
    path[1] = address(TOKEN_TO_BURN);

    IDEXROUTER.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: (msg.value * BURN_PERCENT) / 100 }(0, path, 0x000000000000000000000000000000000000dEaD, block.timestamp);

    // Emit lock created event
    emit LockCreated(msg.sender, _tokenAddress, _depositAmount.length);
  }

  // Claim unlocked tokens
  function withdrawUnlockedTokens(uint64 _index, uint _amount) external nonReentrant withdrawOwner(_index) {
    require(_amount <= getClaimableTokens(_index), "Exceeds withdraw balance");
    require(_amount > 0, "Cannot withdraw 0 tokens");
    address _address = VESTING_INSTANCE[_index].tokenAddress;

    // Subtract amount withdrawn from current amount
    VESTING_INSTANCE[_index].currentAmount -= _amount;
    // Transfer tokens from contract to recipient
    IERC20Upgradeable(VESTING_INSTANCE[_index].tokenAddress).safeTransfer(msg.sender, _amount);

    // Delete vesting instance if no tokens are left
    if (VESTING_INSTANCE[_index].currentAmount == 0) {
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

  // Set router address
  function setRouter(address _routerAddress) external onlyOwner {
    IDEXROUTER = IDEXRouter(_routerAddress);
  }

  // Set referral contract
  function setReferralContract(address _referralAddress) external onlyOwner {
    IMOONLABSREFERRAL = IMoonLabsReferral(_referralAddress);
  }

  // Change lock price in wei
  function setLockPrice(uint _lockPrice) external onlyOwner {
    LOCK_PRICE = _lockPrice;
  }

  // Set referral code discount
  function setCodeDiscount(uint _codeDiscount) external onlyOwner {
    CODE_DISCOUNT = _codeDiscount;
  }

  // Set referral code commission
  function setCodeCommission(uint _codeCommission) external onlyOwner {
    CODE_COMMISSION = _codeCommission;
  }

  // Change token to auto burn
  function setTokenToBurn(address _tokenToBurn) external onlyOwner {
    TOKEN_TO_BURN = IERC20Upgradeable(_tokenToBurn);
  }

  // Change amount of tokens to auto burn
  function setBurnPercent(uint8 _burnPercent) external onlyOwner {
    require(_burnPercent <= 100, "Burn percent cannot exceed 100");
    BURN_PERCENT = _burnPercent;
  }

  // // Return vesting index from owner address
  function getVestingIndexFromCreatorAddress(address _creatorAddress) external view returns (uint64[] memory) {
    return CREATOR_TO_LOCK[_creatorAddress];
  }

  // Return vesting index from withdraw address
  function getVestingIndexFromWithdrawAddress(address _withdrawAddress) external view returns (uint64[] memory) {
    return WITHDRAW_TO_LOCK[_withdrawAddress];
  }

  // Return vest index from token address
  function getVestingIndexFromTokenAddress(address _tokenAddress) external view returns (uint64[] memory) {
    return TOKEN_TO_LOCK[_tokenAddress];
  }

  // Return vesting instance from index
  function getVestingInstance(uint64 _index) external view returns (VestingInstance memory) {
    return VESTING_INSTANCE[_index];
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  // Create vesting instance
  function createVestingInstance(address _tokenAddress, address _withdrawAddress, uint _depositAmount, uint64 _startDate, uint64 _endDate) private {
    require(_depositAmount > 0, "Deposit amount must be greater than 0");
    require(_startDate < _endDate, "Start date must come before end date");
    require(_endDate < 10000000000, "Invalid end date");

    // Create new VestingInstance struct and add to index
    VESTING_INSTANCE[INDEX] = VestingInstance(_tokenAddress, msg.sender, _withdrawAddress, _depositAmount, _depositAmount, _startDate, _endDate);

    // Create map to withdraw address
    WITHDRAW_TO_LOCK[_withdrawAddress].push(INDEX);

    // Create map to token address
    TOKEN_TO_LOCK[_tokenAddress].push(INDEX);

    // Create map to creator address
    CREATOR_TO_LOCK[msg.sender].push(INDEX);

    // Increment index
    INDEX++;
  }

  function transferTokens(address _tokenAddress, uint totalDepositAmount, address _sender) private {
    // Transfer tokens to contract
    IERC20Upgradeable(_tokenAddress).safeTransferFrom(_sender, address(this), totalDepositAmount);
  }

  // Delete vesting instance
  function deleteVestingInstance(uint64 _index) private {
    address withdrawAddress = VESTING_INSTANCE[_index].withdrawAddress;
    address tokenAddress = VESTING_INSTANCE[_index].tokenAddress;

    // Delete mapping from withdraw owner to index
    uint64[] storage withdrawArray = WITHDRAW_TO_LOCK[VESTING_INSTANCE[_index].withdrawAddress];
    for (uint64 i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _index) {
        // Shift down following indexes and overwrite deleted index
        for (uint64 j = i; j < withdrawArray.length - 1; j++) {
          withdrawArray[j] = withdrawArray[j + 1];
        }
        // Remove last index
        withdrawArray.pop();
      }
    }
    // // Delete mapping from creator address to index
    uint64[] storage creatorArray = CREATOR_TO_LOCK[VESTING_INSTANCE[_index].creatorAddress];
    for (uint64 i = 0; i < creatorArray.length; i++) {
      if (creatorArray[i] == _index) {
        // Shift down following indexes and overwrite deleted index
        for (uint64 j = i; j < creatorArray.length - 1; j++) {
          creatorArray[j] = creatorArray[j + 1];
        }
        // Remove last index
        creatorArray.pop();
      }
    }

    // Delete mapping from token address to index
    uint64[] storage tokenArray = TOKEN_TO_LOCK[VESTING_INSTANCE[_index].tokenAddress];
    for (uint64 i = 0; i < tokenArray.length; i++) {
      if (tokenArray[i] == _index) {
        // Shift down following indexes and overwrite deleted index
        for (uint64 j = i; j < tokenArray.length - 1; j++) {
          tokenArray[j] = tokenArray[j + 1];
        }
        // Remove last index
        tokenArray.pop();
      }
    }

    // Delete vesting instance map
    delete VESTING_INSTANCE[_index];

    // Emit deletion event
    emit LockDeleted(withdrawAddress, tokenAddress, _index);
  }

  // Get the current amount of unlocked tokens
  function calculateLinearWithdraw(uint64 _index) private view returns (uint unlockedTokens) {
    uint64 endDate = VESTING_INSTANCE[_index].endDate;
    uint64 startDate = VESTING_INSTANCE[_index].startDate;
    uint currentAmount = VESTING_INSTANCE[_index].currentAmount;
    uint depositAmount = VESTING_INSTANCE[_index].depositAmount;
    uint64 timeBlock = endDate - startDate; // Time from start date to end date
    uint64 timeElapsed;

    if (endDate <= block.timestamp) {
      timeElapsed = timeBlock;
    } else if (startDate < block.timestamp) {
      timeElapsed = uint64(block.timestamp) - startDate;
    }

    // Math to calculate linear unlock
    /*
    This formula will only return a negative number when the current amount is less than what can actually be withdrawn

      Deposit Amount x Time Elapsed
      -----------------------------   -   (Deposit Amount - Current Amount)
               Time Block
    */
    return MathUpgradeable.mulDiv(depositAmount, timeElapsed, timeBlock) - (depositAmount - currentAmount);
  }

  // Distribute commission
  function distributeCommission(string memory _code, uint _value) private {
    address payable to = payable(IMOONLABSREFERRAL.getAddressByCode(_code));
    to.transfer(_value);
  }
}
