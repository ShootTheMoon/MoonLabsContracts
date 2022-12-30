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
// Website: https://www.moonlabs.site/

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.17;

interface IMoonLabsReferral {
  function checkIfActive(bytes32 _code) external view returns (bool);

  function getCodeByAddress(address _address) external view returns (bytes32);

  function getAddressByCode(bytes32 _code) external view returns (address);

  function addRewardsEarned(bytes32 _code, uint _value) external;
}

contract MoonLabsReferralOld is IMoonLabsReferral, Ownable {
  /*|| === STATE VARIABLES === ||*/
  int public index;
  bytes32[] private reservedCodes;
  address[] public moonLabsContracts;

  /*|| === MAPPINGS === ||*/
  mapping(address => bytes32) private addressToCode;
  mapping(bytes32 => address) private codeToAddress;
  mapping(bytes32 => uint) private rewardsEarned;

  /*|| === PUBLIC FUNCTIONS === ||*/
  // Check if code is in use
  function checkIfActive(bytes32 _code) public view override returns (bool) {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    // Check if code is in use
    if (codeToAddress[_c] == address(0)) return false;
    return true;
  }

  //  Check if code is reserved
  function checkIfReserved(bytes32 _code) public view returns (bool) {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    for (uint16 i = 0; i < reservedCodes.length; i++) {
      // Comapre two strings
      if (_c == reservedCodes[i]) return true;
    }
    return false;
  }

  // Remove code from reserved list and pop array
  function removeReservedCode(bytes32 _code) public onlyOwner {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    // Check if code is reserved
    require(checkIfReserved(_c) == true, "Code not reserved");
    for (uint16 i = 0; i < reservedCodes.length; i++) {
      // Comapre two strings
      if (_c == reservedCodes[i]) {
        reservedCodes[i] = reservedCodes[reservedCodes.length - 1];
        reservedCodes.pop();
        break;
      }
    }
  }

  /*|| === EXTERNAL FUNCTIONS === ||*/
  // Create a referral code that is bound to caller address
  function createCode(bytes32 _code) external {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    // Check if code is in use
    require(checkIfActive(_code) == false, "Code in use");
    // Check if caller address has a code
    require(addressToCode[msg.sender] == bytes32(""), "Address in use");
    // Check if code is reserved
    require(checkIfReserved(_c) == false, "Code reserved");
    // Create new mappings
    addressToCode[msg.sender] = _c;
    codeToAddress[_c] = msg.sender;
    index++;
  }

  function deleteCode() external {
    // Check if address has a code
    bytes32 _c = upper(addressToCode[msg.sender]);
    // Check if code is in use
    require(_c != bytes32(""), "Address not in use");
    delete codeToAddress[_c];
    delete addressToCode[msg.sender];
    delete rewardsEarned[_c];
    index--;
  }

  // Change address of referral code
  function setCodeAddress(bytes32 _code, address _address) external {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    // Check if sender owns code
    require(msg.sender == codeToAddress[_c], "You do not own this code");
    // Check if recipient address has a code
    require(addressToCode[_address] == bytes32(""), "Address in use");
    // Reset amount earned
    delete rewardsEarned[_c];
    // Create new mappings
    addressToCode[_address] = _c;
    codeToAddress[_c] = _address;
  }

  function getCodeByAddress(address _address) external view override returns (bytes32) {
    return addressToCode[_address];
  }

  function getAddressByCode(bytes32 _code) external view override returns (address) {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    return codeToAddress[_c];
  }

  // Reserve referral code(s) and push to array
  function addReservedCodes(bytes32[] calldata _code) external onlyOwner {
    for (uint8 i = 0; i < _code.length; i++) {
      // Convert input to uppercase
      bytes32 _c = upper(_code[i]);
      // Check if code is in use
      require(codeToAddress[_c] == address(0), "Code in use");
      // Check if code is reserved
      require(checkIfReserved(_c) == false, "Code is reserved");
      // Push code to reserved list
      reservedCodes.push(_c);
    }
  }

  // Assign a code from reserved list to given address
  function assignReservedCode(bytes32 _code, address _address) external onlyOwner {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    // Check if code is not reserved
    require(checkIfReserved(_c) == true, "Code not reserved");
    // Check if recipient address has a code
    require(addressToCode[_address] == bytes32(""), "Address in use");
    // Remove code from reserved list
    removeReservedCode(_c);
    // Create new mappings
    addressToCode[_address] = _c;
    codeToAddress[_c] = _address;
    index++;
  }

  function deleteCodeOwner(bytes32 _code) external onlyOwner {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    // Check if code is bound to an address
    require(checkIfActive(_code) == true, "Code not in use");
    // Delete mappings
    delete addressToCode[codeToAddress[_c]];
    delete codeToAddress[_c];
    delete rewardsEarned[_c];
    index--;
  }

  // Add address to approved mlab contracts
  function addMoonLabsContract(address _address) external onlyOwner {
    moonLabsContracts.push(_address);
  }

  // Remove address to approved mlab contracts
  function removeMoonLabsContract(address _address) external onlyOwner {
    for (uint32 i = 0; i < moonLabsContracts.length; i++) {
      if (_address == moonLabsContracts[i]) {
        moonLabsContracts[i] = moonLabsContracts[moonLabsContracts.length - 1];
        moonLabsContracts.pop();
      }
    }
  }

  // Function is used inside other mlab contracts
  function addRewardsEarned(bytes32 _code, uint _value) external override {
    for (uint32 i = 0; i < moonLabsContracts.length; i++) {
      if (msg.sender == moonLabsContracts[i]) {
        bytes32 _c = upper(_code);
        // Add rewards to mapping
        rewardsEarned[_c] += _value;
      } else {
        revert();
      }
    }
  }

  // Get rewards a referal code has earned on that current address
  function getRewardsEarned(bytes32 _code) external view returns (uint) {
    // Convert input to uppercase
    bytes32 _c = upper(_code);
    return rewardsEarned[_c];
  }

  /*|| === PRIVATE FUNCTIONS === ||*/
  /**
   * Upper
   *
   * Converts all the values of a string to their corresponding upper case
   * value.
   *
   * @param _base When being used for a data type this is the extended object
   *              otherwise this is the string base to convert to upper case
   * @return string
   */
  function upper(bytes32 _base) public pure returns (bytes32) {
    bytes memory _baseBytes = bytes(abi.encodePacked(_base));
    for (uint i = 0; i < _baseBytes.length; i++) {
      _baseBytes[i] = _upper(_baseBytes[i]);
    }
    return bytes32(_baseBytes);
  }

  /**
   * Upper
   *
   * Convert an alphabetic character to upper case and return the original
   * value when not alphabetic
   *
   * @param _b1 The byte to be converted to upper case
   * @return bytes1 The converted value if the passed value was alphabetic
   *                and in a lower case otherwise returns the original value
   */
  function _upper(bytes1 _b1) private pure returns (bytes1) {
    if (_b1 >= 0x61 && _b1 <= 0x7A) {
      return bytes1(uint8(_b1) - 32);
    }

    return _b1;
  }
}
