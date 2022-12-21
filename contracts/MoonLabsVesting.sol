// SPDX-License-Identifier: MIT

// ███╗   ███╗ ██████╗  ██████╗ ███╗   ██╗    ██╗      █████╗ ██████╗ ███████╗
// ████╗ ████║██╔═══██╗██╔═══██╗████╗  ██║    ██║     ██╔══██╗██╔══██╗██╔════╝
// ██╔████╔██║██║   ██║██║   ██║██╔██╗ ██║    ██║     ███████║██████╔╝███████╗
// ██║╚██╔╝██║██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══██║██╔══██╗╚════██║
// ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║ ╚████║    ███████╗██║  ██║██████╔╝███████║
// ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝
// © 2022 Moon Labs LLC
// Moon Labs LLC reserves all rights on this code.
// You may not, except otherwise with prior permission and express written consent by Moon Labs LLC, copy, download, print, extract, exploit,
// adapt, edit, modify, republish, reproduce, rebroadcast, duplicate, distribute, or publicly display any of the content, information, or material
// on this smart contract for non-personal or commercial purposes, except for any other use as permitted by the applicable copyright law.
//
// Website: https://www.moonlabs.site/

pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./IDEXRouter.sol";

contract MoonLabsVesting is ReentrancyGuardUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  function initialize(address _tokenToBurn, uint _burnPercent, uint _lockPrice, address _routerAddress) public initializer {
    __Ownable_init();
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
    burnPercent = _burnPercent;
    lockPrice = _lockPrice;
    iDEXRouter = IDEXRouter(_routerAddress);
  }

  /*|| === STATE VARIABLES === ||*/
  uint public index;
  uint public burnPercent;
  uint public lockPrice;
  IERC20Upgradeable public tokenToBurn;
  IDEXRouter public iDEXRouter;

  /*|| === STRUCTS VARIABLES === ||*/
  struct VestingInstance {
    address tokenAddress; // Address of locked token
    address creatorAddress; // Lock creator
    address withdrawAddress; // Withdraw address
    uint depositAmount; // Initial deposit amount
    uint currentAmount; // Current tokens in lock
    uint startDate; // Linear lock if !=0. Date when tokens start to unlock
    uint endDate; // Date when tokens are fully unlocked
  }

  /*|| === MAPPING === ||*/
  mapping(address => uint[]) private creatorAddressToLock;
  mapping(address => uint[]) private withdrawAddressToLock;
  mapping(address => uint[]) private tokenAddressToLock;
  mapping(uint => VestingInstance) private vestingInstance;

  /*|| === MODIFIERS === ||*/
  modifier withdrawOwner(uint _index) {
    require(msg.sender == vestingInstance[_index].withdrawAddress, "You do not own this lock");
    _;
  }

  /*|| === EVENTS === ||*/
  event LockCreated(address indexed creator, address indexed token, uint indexed numOfLocks);
  event TokensWithdrawn(address indexed from, address indexed token, uint index);
  event LockTransfered(address indexed from, address indexed to, uint index);
  event LockDeleted(address indexed withdrawAddress, address indexed token, uint index);

  /*|| === PUBLIC FUNCTIONS === ||*/
  // Return claimable tokens
  function getClaimableTokens(uint _index) public view returns (uint) {
    uint _currentAmount = vestingInstance[_index].currentAmount;
    uint _endDate = vestingInstance[_index].endDate;
    uint _startDate = vestingInstance[_index].startDate;

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
  function transferVestingOwnership(uint _index, address _newOwner) public withdrawOwner(_index) {
    // Change withdraw owner in vesting isntance to new owner
    vestingInstance[_index].withdrawAddress = _newOwner;

    // Delete mapping from old owner to index of vesting instance and pop
    uint[] storage withdrawArray = withdrawAddressToLock[msg.sender];
    for (uint i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _index) {
        for (uint j = i; j < withdrawArray.length - 1; j++) {
          withdrawArray[j] = withdrawArray[j + 1];
        }
        withdrawArray.pop();
      }
    }
    // Map index of transferred lock to new owner
    withdrawAddressToLock[_newOwner].push(_index);
    emit LockTransfered(msg.sender, _newOwner, _index);
  }

  /*|| === EXTERNAL FUNCTIONS === ||*/
  // Create lock or vesting instance
  function createLock(address _tokenAddress, address[] calldata _withdrawAddress, uint[] calldata _depositAmount, uint[] calldata _startDate, uint[] calldata _endDate) external payable nonReentrant {
    // Check if all arrays are same the size
    require(_withdrawAddress.length == _depositAmount.length && _depositAmount.length == _endDate.length && _endDate.length == _startDate.length, "Unequal array lengths");
    require(msg.value == lockPrice * _withdrawAddress.length, "Incorrect Price");

    uint _totalDepositAmount;

    for (uint i; i < _withdrawAddress.length; i++) {
      createVestingInstance(_tokenAddress, _withdrawAddress[i], _depositAmount[i], _startDate[i], _endDate[i]);
      _totalDepositAmount += _depositAmount[i];
    }

    // Transfer tokens to contract
    IERC20Upgradeable(_tokenAddress).safeTransferFrom(msg.sender, address(this), _totalDepositAmount);

    // Buy tokenToBurn via uniswap router and send to dead address
    address[] memory path = new address[](2);
    path[0] = iDEXRouter.WETH();
    path[1] = address(tokenToBurn);

    iDEXRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: (msg.value * burnPercent) / 100 }(0, path, 0x000000000000000000000000000000000000dEaD, block.timestamp);

    // Emit lock created event
    emit LockCreated(msg.sender, _tokenAddress, _withdrawAddress.length);
  }

  // Claim unlocked tokens
  function withdrawUnlockedTokens(uint _index, uint _amount) external nonReentrant withdrawOwner(_index) {
    require(_amount <= getClaimableTokens(_index), "Exceeds withdraw balance");
    require(_amount > 0, "Cannot withdraw 0 tokens");
    address _address = vestingInstance[_index].tokenAddress;

    // Subtract amount withdrawn from current amount
    vestingInstance[_index].currentAmount -= _amount;
    // Transfer tokens from contract to recipient
    IERC20Upgradeable(vestingInstance[_index].tokenAddress).safeTransfer(msg.sender, _amount);

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

  // Set router address
  function setRouter(address _routerAddress) external onlyOwner {
    iDEXRouter = IDEXRouter(_routerAddress);
  }

  // Change lock price in wei
  function setLockPrice(uint _lockPrice) external onlyOwner {
    lockPrice = _lockPrice;
  }

  // Change token to auto burn
  function setTokenToBurn(address _tokenToBurn) external onlyOwner {
    tokenToBurn = IERC20Upgradeable(_tokenToBurn);
  }

  // Change amount of tokens to auto burn
  function setBurnPercent(uint _burnPercent) external onlyOwner {
    require(_burnPercent <= 100, "Burn percent cannot exceed 100");
    burnPercent = _burnPercent;
  }

  // Return vesting index from owner address
  function getVestingIndexFromCreatorAddress(address _creatorAddress) external view returns (uint[] memory) {
    return creatorAddressToLock[_creatorAddress];
  }

  // Return vesting index from withdraw address
  function getVestingIndexFromWithdrawAddress(address _withdrawAddress) external view returns (uint[] memory) {
    return withdrawAddressToLock[_withdrawAddress];
  }

  // Return vest index from token address
  function getVestingIndexFromTokenAddress(address _tokenAddress) external view returns (uint[] memory) {
    return tokenAddressToLock[_tokenAddress];
  }

  // Return vesting instance from index
  function getVestingInstance(uint _index) external view returns (VestingInstance memory) {
    return vestingInstance[_index];
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  // Create vesting instance
  function createVestingInstance(address _tokenAddress, address _withdrawAddress, uint _depositAmount, uint _startDate, uint _endDate) private {
    require(_depositAmount > 0, "Deposit amount must be greater than 0");
    require(_startDate < _endDate, "Start date must come before end date");
    require(_endDate < 10000000000, "Invalid end date");

    // Create new VestingInstance struct and add to index
    vestingInstance[index] = VestingInstance(_tokenAddress, msg.sender, _withdrawAddress, _depositAmount, _depositAmount, _startDate, _endDate);

    // Create map to withdraw address
    withdrawAddressToLock[_withdrawAddress].push(index);

    // Create map to token address
    tokenAddressToLock[_tokenAddress].push(index);

    // Create map to creator address
    creatorAddressToLock[msg.sender].push(index);

    // Increment index
    index++;
  }

  // Delete vesting instance
  function deleteVestingInstance(uint _index) private {
    address _withdrawAddress = vestingInstance[_index].withdrawAddress;
    address _tokenAddress = vestingInstance[_index].tokenAddress;

    // Delete mapping from withdraw owner to index
    uint[] storage withdrawArray = withdrawAddressToLock[vestingInstance[_index].withdrawAddress];
    for (uint i = 0; i < withdrawArray.length; i++) {
      if (withdrawArray[i] == _index) {
        // Shift down following indexes and overwrite deleted index
        for (uint j = i; j < withdrawArray.length - 1; j++) {
          withdrawArray[j] = withdrawArray[j + 1];
        }
        // Remove last index
        withdrawArray.pop();
      }
    }
    // Delete mapping from creator address to index
    uint[] storage creatorArray = creatorAddressToLock[vestingInstance[_index].creatorAddress];
    for (uint i = 0; i < creatorArray.length; i++) {
      if (creatorArray[i] == _index) {
        // Shift down following indexes and overwrite deleted index
        for (uint j = i; j < creatorArray.length - 1; j++) {
          creatorArray[j] = creatorArray[j + 1];
        }
        // Remove last index
        creatorArray.pop();
      }
    }
    // Delete mapping from token address to index
    uint[] storage tokenArray = tokenAddressToLock[vestingInstance[_index].tokenAddress];
    for (uint i = 0; i < tokenArray.length; i++) {
      if (tokenArray[i] == _index) {
        // Shift down following indexes and overwrite deleted index
        for (uint j = i; j < tokenArray.length - 1; j++) {
          tokenArray[j] = tokenArray[j + 1];
        }
        // Remove last index
        tokenArray.pop();
      }
    }

    // Delete vesting instance map
    delete vestingInstance[_index];

    // Emit deletion event
    emit LockDeleted(_withdrawAddress, _tokenAddress, _index);
  }

  // Get the current amount of unlocked tokens
  function calculateLinearWithdraw(uint _index) private view returns (uint unlockedTokens) {
    uint _endDate = vestingInstance[_index].endDate;
    uint _startDate = vestingInstance[_index].startDate;
    uint _currentAmount = vestingInstance[_index].currentAmount;
    uint _depositAmount = vestingInstance[_index].depositAmount;
    uint _timeBlock = _endDate - _startDate; // Time from start date to end date
    uint _timeElapsed;

    if (_endDate <= block.timestamp) {
      _timeElapsed = _timeBlock;
    } else if (_startDate < block.timestamp) {
      _timeElapsed = block.timestamp - _startDate;
    }

    // Math to calculate linear unlock
    /*
    This formula will only return a negative number when the current amount is less than what can actually be withdrawn

      Deposit Amount x Time Elapsed
      -----------------------------   -   (Deposit Amount - Current Amount)
               Time Block
    */
    return MathUpgradeable.mulDiv(_depositAmount, _timeElapsed, _timeBlock) - (_depositAmount - _currentAmount);
  }
}
