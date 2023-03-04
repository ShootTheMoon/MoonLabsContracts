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
 * @title This is a contract used for creating whitelists for Moon Labs products
 * @author Moon Labs LLC
 * @notice  This contract's intended purpose is for users to purchase whitelists for their desired tokens. Whitelisting a token allows for all fees on
 * related Moon Labs products to be waived. Whitelists may not be transferred from token to token.
 */

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MoonLabsStakingCards is ERC721Enumerable, Ownable {
  using Strings for uint;

  constructor(string memory name, string memory symbol, string memory _baseTokenURI) ERC721(name, symbol) {
    baseTokenURI = _baseTokenURI;
    for (uint i = 1; i <= maxSupply; i++) {
      _safeMint(msg.sender, i);
    }
  }

  /*|| === STATE VARIABLES === ||*/
  string public baseExtension = ".json";
  uint public maxSupply = 500;
  string private baseTokenURI;

  /*|| === EXTERNAL FUNCTIONS === ||*/
  function setBaseURI(string memory baseURI) external onlyOwner {
    baseTokenURI = baseURI;
  }

  /*|| === PUBLIC FUNCTIONS === ||*/
  function claimETH() public payable onlyOwner {
    (bool success, ) = payable(msg.sender).call{ value: address(this).balance }("");
    require(success);
  }

  // Get Token List
  function getTokenIds(address _owner) public view returns (uint[] memory) {
    // Count owned Token
    uint ownerTokenCount = balanceOf(_owner);
    uint[] memory tokenIds = new uint[](ownerTokenCount);
    // Get ids of owned Token
    for (uint i; i < ownerTokenCount; i++) {
      tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
    }
    return tokenIds;
  }

  // Return compiled Token URI
  function tokenURI(uint _id) public view virtual override returns (string memory) {
    require(_exists(_id), "URI query for nonexistent token");
    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0 ? string(abi.encodePacked(currentBaseURI, _id.toString(), baseExtension)) : "";
  }

  /*|| === INTERNAL FUNCTIONS === ||*/

  // URI Handling
  function _baseURI() internal view virtual override returns (string memory) {
    return baseTokenURI;
  }
}
