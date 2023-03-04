// SPDX-License-Identifier: MIT

/**
 * ███╗   ███╗ ██████╗  ██████╗ ███╗   ██╗    ██╗      █████╗ ██████╗ ███████╗
 * ████╗ ████║██╔═══██╗██╔═══██╗████╗  ██║    ██║     ██╔══██╗██╔══██╗██╔════╝
 * ██╔████╔██║██║   ██║██║   ██║██╔██╗ ██║    ██║     ███████║██████╔╝███████╗
 * ██║╚██╔╝██║██║   ██║██║   ██║██║╚██╗██║    ██║     ██╔══██║██╔══██╗╚════██║
 * ██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║ ╚████║    ███████╗██║  ██║██████╔╝███████║
 * ╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝    ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝
 */

pragma solidity 0.8.17;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MoonLabs is ERC20, Ownable {
  /*|| === STATE VARIABLES === ||*/
  uint public launchDate;
  uint public nftThreshold = 0.01 ether;
  uint16 public nftIndex = 1;
  uint public nftBalance;
  address payable public treasuryWallet;
  address payable public teamWallet;
  address payable public liqWallet;
  address public immutable uniswapV2Pair;
  IUniswapV2Router02 public immutable uniswapV2Router;
  IERC721 public immutable nftContract;
  bool private inSwapAndLiquify;
  bool public launched;
  BuyTax public buyTax;
  SellTax public sellTax;

  uint private _supply = 100000000;
  uint8 private _decimals = 9;
  string private _name = "Moon Labs";
  string private _symbol = "MLAB";
  uint public swapThreshold = 200000 * 10 ** _decimals;
  bool public taxSwap = true;

  /*|| === STRUCTS === ||*/
  struct BuyTax {
    uint8 liquidityTax;
    uint8 treasuryTax;
    uint8 teamTax;
    uint8 burnTax;
    uint8 nftTax;
    uint8 totalTax;
  }

  struct SellTax {
    uint8 liquidityTax;
    uint8 treasuryTax;
    uint8 teamTax;
    uint8 burnTax;
    uint8 nftTax;
    uint8 totalTax;
  }

  /*|| === MAPPINGS === ||*/
  mapping(address => bool) public excludedFromFee;

  /*|| === CONSTRUCTOR === ||*/
  constructor(address payable _treasuryWallet, address payable _teamWallet, address payable _liqWallet, address nftAddress) ERC20(_name, _symbol) {
    _mint(msg.sender, (_supply * 10 ** _decimals)); /// Mint and send all tokens to deployer
    treasuryWallet = _treasuryWallet;
    teamWallet = _teamWallet;
    liqWallet = _liqWallet;

    nftContract = IERC721(nftAddress);

    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH()); /// Create uniswap pair

    uniswapV2Router = _uniswapV2Router;

    excludedFromFee[address(uniswapV2Router)] = true;
    excludedFromFee[msg.sender] = true;
    excludedFromFee[treasuryWallet] = true;
    excludedFromFee[teamWallet] = true;
    excludedFromFee[liqWallet] = true;

    buyTax = BuyTax(10, 10, 10, 10, 20, 60);
    sellTax = SellTax(10, 10, 10, 10, 20, 60);
  }

  /*|| === MODIFIERS === ||*/
  modifier lockTheSwap() {
    inSwapAndLiquify = true;
    _;
    inSwapAndLiquify = false;
  }

  /*|| === RECIEVE FUNCTION === ||*/
  receive() external payable {}

  /*|| === EXTERNAL FUNCTIONS === ||*/

  /**
   * @notice Enables initial trading and logs time of activation. Once trading is started it cannot be stopped.
   */
  function launch() external onlyOwner {
    launched = true;
    launchDate = block.timestamp;
  }

  function setNftThreshold(uint _nftThreshold) external onlyOwner {
    nftThreshold = _nftThreshold;
  }

  function setTreasuryWallet(address payable _treasuryWallet) external onlyOwner {
    require(_treasuryWallet != address(0), "Address cannot be 0 address");
    treasuryWallet = _treasuryWallet;
  }

  function setTeamWallet(address payable _teamWallet) external onlyOwner {
    require(_teamWallet != address(0), "Address cannot be 0 address");
    teamWallet = _teamWallet;
  }

  function setLiqWallet(address payable _liqWallet) external onlyOwner {
    require(_liqWallet != address(0), "Address cannot be 0 address");
    liqWallet = _liqWallet;
  }

  function addToWhitelist(address _address) external onlyOwner {
    excludedFromFee[_address] = true;
  }

  function removeFromWhitelist(address _address) external onlyOwner {
    excludedFromFee[_address] = false;
  }

  function setTaxSwap(bool _taxSwap) external onlyOwner {
    taxSwap = _taxSwap;
  }

  function setBuyTax(uint8 liquidityTax, uint8 treasuryTax, uint8 teamTax, uint8 burnTax) external onlyOwner {
    uint8 totalTax = liquidityTax + treasuryTax + teamTax + burnTax + 2;
    require(totalTax <= 12, "ERC20: total tax must not be greater than 10");
    buyTax = BuyTax(liquidityTax * 10, treasuryTax * 10, teamTax * 10, burnTax * 10, 2 * 10, totalTax * 10);
  }

  function setSellTax(uint8 liquidityTax, uint8 treasuryTax, uint8 teamTax, uint8 burnTax) external onlyOwner {
    uint8 totalTax = liquidityTax + treasuryTax + teamTax + burnTax + 2;
    require(totalTax <= 12, "ERC20: total tax must not be greater than 10");
    sellTax = SellTax(liquidityTax * 10, treasuryTax * 10, teamTax * 10, burnTax * 10, 2 * 10, totalTax * 10);
  }

  function setTokensToSellForTax(uint _swapThreshold) external onlyOwner {
    swapThreshold = _swapThreshold;
  }

  /*|| === INTERNAL FUNCTIONS === ||*/
  function _transfer(address from, address to, uint amount) internal override {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");
    require(balanceOf(from) >= amount, "ERC20: transfer amount exceeds balance");

    /// If buy or sell
    if ((from == uniswapV2Pair || to == uniswapV2Pair) && !inSwapAndLiquify) {
      /// On sell and if tax swap enabled
      if (to == uniswapV2Pair && taxSwap) {
        /// If the contract balance reaches sell threshold
        if (balanceOf(address(this)) >= swapThreshold) {
          /// Perform tax swap
          _swapAndDistribute();
        }
      }

      /// Check if nft threshold is met
      if (nftBalance >= nftThreshold) {
        /// Send eth to index holder
        (bool sent, ) = payable(nftContract.ownerOf(nftIndex)).call{ value: nftThreshold }("");
        /// Check if eth sent
        if (sent) {
          nftBalance -= nftThreshold;
        }

        if (nftIndex > 500) {
          nftIndex++;
        } else {
          nftIndex = 1;
        }
      }

      uint transferAmount = amount;
      if (!(excludedFromFee[from] || excludedFromFee[to])) {
        require(launched, "Token not launched");
        uint fees;

        /// On sell
        if (to == uniswapV2Pair) {
          fees = sellTax.totalTax;

          /// On buy
        } else if (from == uniswapV2Pair) {
          fees = buyTax.totalTax;
        }
        uint tokenFees = (amount * fees) / 1000;
        transferAmount -= tokenFees;
        super._transfer(from, address(this), tokenFees);
      }
      super._transfer(from, to, transferAmount);
    } else {
      super._transfer(from, to, amount);
    }
  }

  /*|| === PRIVATE FUNCTIONS === ||*/

  function _swapTokens(uint tokenAmount) private lockTheSwap {
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
  }

  function _swapAndDistribute() private lockTheSwap {
    uint8 totalTokenTax = buyTax.totalTax + sellTax.totalTax;
    uint8 burnTax = buyTax.burnTax + sellTax.burnTax;
    uint8 liquidityTax = buyTax.liquidityTax + sellTax.liquidityTax;

    uint liquidityTokenCut = ((swapThreshold * liquidityTax) / totalTokenTax) / 2;
    uint burnTokenCut;

    /// If burns are enabled
    if (buyTax.burnTax != 0 || sellTax.burnTax != 0) {
      burnTokenCut = (swapThreshold * burnTax) / totalTokenTax;
      /// Send tokens to dead address
      super._transfer(address(this), address(0xdead), burnTokenCut);
    }

    _swapTokens(swapThreshold - liquidityTokenCut - burnTokenCut);

    uint ethBalance = address(this).balance;

    uint totalEthFee = (totalTokenTax - (liquidityTax / 2) - burnTax);

    /// Distribute to team and treasury
    (treasuryWallet).call{ value: (ethBalance * buyTax.treasuryTax + sellTax.treasuryTax) / totalEthFee }("");
    (teamWallet).call{ value: (ethBalance * buyTax.teamTax + sellTax.teamTax) / totalEthFee }("");

    /// Add ETH to nft balance
    nftBalance += (ethBalance * buyTax.nftTax + sellTax.nftTax) / totalEthFee;

    /// Add tokens to liquidity
    _addLiquidity((liquidityTokenCut), ((ethBalance * liquidityTax) / totalEthFee) / 2);
  }

  function _addLiquidity(uint tokenAmount, uint ethAmount) private lockTheSwap {
    _approve(address(this), address(uniswapV2Router), tokenAmount);
    uniswapV2Router.addLiquidityETH{ value: ethAmount }(address(this), tokenAmount, 0, 0, liqWallet, block.timestamp);
  }
}
