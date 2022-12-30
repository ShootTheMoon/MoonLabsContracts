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
 * @title This is a contract used for creating and managing referral codes.
 * @author Moon Labs LLC
 * @notice This contract's intended purpose is to allow users to create referral codes for customers to use while purchasing Moon Labs products. There
 * may only be one referral code per address and one address per referral code. Code owners may check their commission earned via this contract. Reserved
 * codes are bound to no address and may not be used until bound to an address.
 */

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.17;

interface IMoonLabsReferral {
  function checkIfActive(string calldata code) external view returns (bool);

  function getCodeByAddress(address _address) external view returns (string memory);

  function getAddressByCode(string memory code) external view returns (address);

  function addRewardsEarned(string calldata code, uint commission) external;
}

contract MoonLabsReferral is IMoonLabsReferral, Ownable {
  /*|| === STATE VARIABLES === ||*/
  int public index; /// Index keeps track of active referral codes
  string[] private reservedCodes; /// Reserved codes not bound to an address
  address[] public moonLabsContracts; /// Array of verified Moon Labs contracts

  /*|| === MAPPINGS === ||*/
  mapping(address => string) private addressToCode;
  mapping(string => address) private codeToAddress;
  mapping(string => uint) private rewardsEarned; /// Rewards earned by code in WEI

  /*|| === EXTERNAL FUNCTIONS === ||*/
  /**
   * @notice Creates a code to the caller's address. Cannot create a code that is in use and the caller's address cannot be in use.
   * @param code to be bound to address
   * @dev All codes created are converted into uppercase before being stored.
   */
  function createCode(string calldata code) external {
    /// Convert input to uppercase
    string memory _c = upper(code);
    /// Check if the code is in use
    require(checkIfActive(code) == false, "Code in use");
    /// Check if the caller address has a code
    require(keccak256(abi.encodePacked(addressToCode[msg.sender])) == keccak256(abi.encodePacked("")), "Address in use");
    /// Check if the code is reserved
    require(checkIfReserved(_c) == false, "Code reserved");
    /// Create new mappings
    addressToCode[msg.sender] = _c;
    codeToAddress[_c] = msg.sender;
    index++;
  }

  /**
   * @notice Deletes the code bound to the caller address.
   */
  function deleteCode() external {
    /// Check if the address has a code
    string memory _c = upper(addressToCode[msg.sender]);
    /// Check if the code is in use
    require(keccak256(abi.encodePacked(_c)) != keccak256(abi.encodePacked("")), "Address not in use");
    /// Delete mappings
    delete codeToAddress[_c];
    delete addressToCode[msg.sender];
    delete rewardsEarned[_c];
    index--;
  }

  /**
   * @notice Binds a code to new a address and resets commission earned on that code. Only the code owner can transfer their code. The new owner's address must not be in use.
   * @param code to be bound to address
   * @param newOwner address of to which the code will be bound to
   */
  function setCodeAddress(string calldata code, address newOwner) external {
    /// Convert input to uppercase
    string memory _c = upper(code);
    /// Check if the sender owns the code
    require(msg.sender == codeToAddress[_c], "You do not own this code");
    /// Check if the recipient address has a code
    require(keccak256(abi.encodePacked(addressToCode[newOwner])) == keccak256(abi.encodePacked("")), "Address in use");
    /// Reset the amount earned
    delete rewardsEarned[_c];
    /// Create new mappings
    addressToCode[newOwner] = _c;
    codeToAddress[_c] = newOwner;
  }

  /**
   * @notice Adds reserved codes at the array of reserved codes. Codes cannot be in use and codes can not be already reserved. Owner only function.
   * @param code Array of codes
   */
  function addReservedCodes(string[] calldata code) external onlyOwner {
    for (uint8 i = 0; i < code.length; i++) {
      /// Convert input to uppercase
      string memory _c = upper(code[i]);
      /// Check if the code is in use
      require(codeToAddress[_c] == address(0), "Code in use");
      /// Check if the code is reserved
      require(checkIfReserved(_c) == false, "Code is reserved");
      /// Push code to the reserved list
      reservedCodes.push(_c);
    }
  }

  /**
   * @notice Assigns a reserved code to an address. The address must be in use. Owner only function.
   * @param code code to be bound to address
   * @param newOwner address of to which the code will be bound to
   */
  function assignReservedCode(string calldata code, address newOwner) external onlyOwner {
    /// Convert input to uppercase
    string memory _c = upper(code);
    /// Check if the code is not reserved
    require(checkIfReserved(_c) == true, "Code not reserved");
    /// Check if the recipient address has a code
    require(keccak256(abi.encodePacked(addressToCode[newOwner])) == keccak256(abi.encodePacked("")), "Address in use");
    /// Remove code from the reserved list
    removeReservedCode(_c);
    /// Create new mappings
    addressToCode[newOwner] = _c;
    codeToAddress[_c] = newOwner;
    index++;
  }

  /**
   * @notice Delete code from an assigned address. The address must be in use. Owner only function.
   * @param code to be deleted
   */
  function deleteCodeOwner(string calldata code) external onlyOwner {
    /// Convert input to uppercase
    string memory _c = upper(code);
    /// Check if the code is bound to an address
    require(checkIfActive(code) == true, "Code not in use");
    /// Delete mappings
    delete addressToCode[codeToAddress[_c]];
    delete codeToAddress[_c];
    delete rewardsEarned[_c];
    index--;
  }

  /**
   * @notice Add contract address to the Moon Labs contracts array. Owner only function.
   * @param _address address of the Moon Labs contract
   */
  function addMoonLabsContract(address _address) external onlyOwner {
    moonLabsContracts.push(_address);
  }

  /**
   * @notice Remove contract address from the Moon Labs contracts array. Owner only function.
   * @param _address address of the Moon Labs contract
   */
  function removeMoonLabsContract(address _address) external onlyOwner {
    for (uint32 i = 0; i < moonLabsContracts.length; i++) {
      if (_address == moonLabsContracts[i]) {
        moonLabsContracts[i] = moonLabsContracts[moonLabsContracts.length - 1];
        moonLabsContracts.pop();
      }
    }
  }

  /**
   * @notice Log rewards to code mapping. Only callable by Moon Labs contracts.
   * @param code referral code
   * @param commission amount of eth to send to referral code owner
   */
  function addRewardsEarned(string calldata code, uint commission) external override {
    for (uint32 i = 0; i < moonLabsContracts.length; i++) {
      if (msg.sender == moonLabsContracts[i]) {
        string memory _c = upper(code);
        /// Add rewards to mapping
        rewardsEarned[_c] += commission;
      }
    }
  }

  /**
   * @notice Get rewards a referral code has earned on that current address.
   * @param code referral code
   * @return uint number or rewards in ETH earned
   */
  function getRewardsEarned(string calldata code) external view returns (uint) {
    /// Convert input to uppercase
    string memory _c = upper(code);
    return rewardsEarned[_c];
  }

  /**
   * @notice Get a code that is bound to the desired address.
   * @param _address wallet address
   * @return string code bound to input address
   */
  function getCodeByAddress(address _address) external view override returns (string memory) {
    return addressToCode[_address];
  }

  /**
   * @notice Get an address that is bound to the desired code.
   * @param code referral code
   * @return address wallet address of the code owner
   */
  function getAddressByCode(string memory code) external view override returns (address) {
    /// Convert input to uppercase
    string memory _c = upper(code);
    return codeToAddress[_c];
  }

  /*|| === PUBLIC FUNCTIONS === ||*/
  /**
   * @notice Remove code from reserved list. Only owner function.
   * @param code referral code
   */
  function removeReservedCode(string memory code) public onlyOwner {
    /// Convert input to uppercase
    string memory _c = upper(code);
    /// Check if the code is reserved
    require(checkIfReserved(_c) == true, "Code not reserved");
    for (uint16 i = 0; i < reservedCodes.length; i++) {
      /// Comapre two strings
      if (keccak256(abi.encodePacked(_c)) == keccak256(abi.encodePacked(reservedCodes[i]))) {
        reservedCodes[i] = reservedCodes[reservedCodes.length - 1];
        reservedCodes.pop();
      }
    }
  }

  /**
   * @notice Remove code from reserved list. Only owner function.
   * @param code referral code
   * @return bool true if code is active and false if it is not
   */
  function checkIfActive(string calldata code) public view override returns (bool) {
    // Convert input to uppercase
    string memory _c = upper(code);
    // Check if the code is in use
    if (codeToAddress[_c] == address(0)) return false;
    return true;
  }

  /**
   * @notice Check if the code is reserved
   * @param code referral code
   * @return bool true if code is reserved and false if it is not
   */
  function checkIfReserved(string memory code) public view returns (bool) {
    // Convert input to uppercase
    string memory _c = upper(code);
    for (uint16 i = 0; i < reservedCodes.length; i++) {
      // Comapre two strings
      if (keccak256(abi.encodePacked(_c)) == keccak256(abi.encodePacked(reservedCodes[i]))) return true;
    }
    return false;
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  /**
   * @notice Converts all the values of a string to their corresponding upper case value.
   * @param _base When being used for a data type this is the extended object otherwise this is the string base to convert to upper case
   * @return string
   */
  function upper(string memory _base) private pure returns (string memory) {
    bytes memory _baseBytes = bytes(_base);
    for (uint i = 0; i < _baseBytes.length; i++) {
      _baseBytes[i] = _upper(_baseBytes[i]);
    }
    return string(_baseBytes);
  }

  /**
   * @notice Convert an alphabetic character to upper case and return the original value when not alphabetic
   * @param _b1 The byte to be converted to upper case
   * @return bytes1 The converted value if the passed value was alphabetic and in a lower case otherwise returns the original value
   */
  function _upper(bytes1 _b1) private pure returns (bytes1) {
    if (_b1 >= 0x61 && _b1 <= 0x7A) {
      return bytes1(uint8(_b1) - 32);
    }

    return _b1;
  }
}
