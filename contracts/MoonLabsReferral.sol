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

pragma solidity ^0.8.7;

interface IMoonLabsReferral {
  function checkIfActive(string calldata _code) external view returns (bool);

  function getCodeByAddress(address _address) external view returns (string memory);

  function getAddressByCode(string memory _code) external view returns (address);
}

contract MoonLabsReferral is IMoonLabsReferral, Ownable {
  /*|| === STATE VARIABLES === ||*/
  int public INDEX;
  string[] private RESERVED_CODES;

  /*|| === MAPPINGS === ||*/
  mapping(address => string) private ADDRESS_CODE;
  mapping(string => address) private CODE_ADDRESS;

  /*|| === PUBLIC FUNCTIONS === ||*/

  // Check if code is in use
  function checkIfActive(string calldata _code) public view override returns (bool) {
    // Convert input to uppercase
    string memory _c = upper(_code);
    // Check if code is in use
    if (CODE_ADDRESS[_c] == address(0)) return true;
    return false;
  }

  //  Check if code is reserved
  function checkIfReserved(string memory _code) public view returns (bool) {
    // Convert input to uppercase
    string memory _c = upper(_code);
    for (uint16 i = 0; i < RESERVED_CODES.length; i++) {
      // Comapre two strings
      if (keccak256(abi.encodePacked(_c)) == keccak256(abi.encodePacked(RESERVED_CODES[i]))) return true;
    }
    return false;
  }

  // Remove code from reserved list and pop array
  function removeReservedCode(string memory _code) public onlyOwner {
    // Convert input to uppercase
    string memory _c = upper(_code);
    // Check if code is reserved
    require(checkIfReserved(_c) == true, "Code is not reserved");
    for (uint16 i = 0; i < RESERVED_CODES.length; i++) {
      // Comapre two strings
      if (keccak256(abi.encodePacked(_c)) == keccak256(abi.encodePacked(RESERVED_CODES[i]))) {
        RESERVED_CODES[i] = RESERVED_CODES[RESERVED_CODES.length - 1];
        RESERVED_CODES.pop();
      }
    }
  }

  /*|| === EXTERNAL FUNCTIONS === ||*/
  // Create a referal code that is bound to caller address
  function createCode(string calldata _code) external {
    // Convert input to uppercase
    string memory _c = upper(_code);
    // Check if code is in use
    require(checkIfActive(_code) == false, "Code in use");
    // Check if caller address has a code
    require(keccak256(abi.encodePacked(ADDRESS_CODE[msg.sender])) == keccak256(abi.encodePacked("")), "Address in use");
    // Check if code is reserved
    require(checkIfReserved(_c) == false, "Code reserved");
    ADDRESS_CODE[msg.sender] = _c;
    CODE_ADDRESS[_c] = msg.sender;
    INDEX++;
  }

  function deleteCode() external {
    // Check if address has a code
    require(keccak256(abi.encodePacked(ADDRESS_CODE[msg.sender])) != keccak256(abi.encodePacked("")), "Address not in use");
    delete CODE_ADDRESS[ADDRESS_CODE[msg.sender]];
    delete ADDRESS_CODE[msg.sender];
    INDEX--;
  }

  // Change address of referal code
  function setCodeAddress(string calldata _code, address _address) external {
    // Convert input to uppercase
    string memory _c = upper(_code);
    // Check if sender owns code
    require(msg.sender == CODE_ADDRESS[_c], "You do not own this code");
    // Check if caller address has a code
    require(keccak256(abi.encodePacked(ADDRESS_CODE[_address])) == keccak256(abi.encodePacked("")), "Address not in use");
    ADDRESS_CODE[_address] = _c;
    CODE_ADDRESS[_c] = _address;
  }

  function getCodeByAddress(address _address) external view override returns (string memory) {
    return ADDRESS_CODE[_address];
  }

  function getAddressByCode(string memory _code) external view override returns (address) {
    // Convert input to uppercase
    string memory _c = upper(_code);
    return CODE_ADDRESS[_c];
  }

  // Reserve referal code(s) and push to array
  function addReservedCodes(string[] calldata _code) external onlyOwner {
    for (uint8 i = 0; i < _code.length; i++) {
      // Convert input to uppercase
      string memory _c = upper(_code[i]);
      // Check if code is in use
      require(CODE_ADDRESS[_c] == address(0), "Code in use");
      // Check if code is reserved
      require(checkIfReserved(_c) == false, "Code is reserved");
      // Push code to reserved list
      RESERVED_CODES.push(_c);
    }
  }

  // Assign a code from reserved list to given address
  function assignReservedCode(string calldata _code, address _address) external onlyOwner {
    // Convert input to uppercase
    string memory _c = upper(_code);
    // Check if code is not reserved
    require(checkIfReserved(_c) == true, "Code is not reserved");
    // Remove code from reserved list
    removeReservedCode(_c);
    ADDRESS_CODE[_address] = _c;
    CODE_ADDRESS[_c] = _address;
    INDEX++;
  }

  function deleteCodeOwner(string calldata _code) external onlyOwner {
    // Convert input to uppercase
    string memory _c = upper(_code);
    // Check if code is bound to an address
    require(checkIfActive(_code) == false, "Code in use");
    // Check if code is reserved
    require(checkIfReserved(_c) == false, "Code is reserved");
    delete ADDRESS_CODE[CODE_ADDRESS[_c]];
    delete CODE_ADDRESS[_c];
    INDEX--;
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
  function upper(string memory _base) private pure returns (string memory) {
    bytes memory _baseBytes = bytes(_base);
    for (uint i = 0; i < _baseBytes.length; i++) {
      _baseBytes[i] = _upper(_baseBytes[i]);
    }
    return string(_baseBytes);
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
