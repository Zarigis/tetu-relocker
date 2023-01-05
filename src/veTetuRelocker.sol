

// SPDX-License-Identifier: MIT


pragma solidity ^0.8.13;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../lib/ops/contracts/integrations/OpsReady.sol";

interface veTetu {
  function increaseUnlockTime(uint _tokenId, uint _lockDuration) external returns (uint power, uint unlockDate);
  function isApprovedOrOwner(address _spender, uint _tokenId) external view returns (bool);
  function ownerOf(uint _tokenId) external view returns (address);
  function lockedEnd(uint _tokenId) external view returns (uint);
  function setApprovalForAll(address _operator, bool _approved) external;
}

interface WMatic {
  function withdraw(uint256 wad) external;
}

contract veTetuRelocker is OpsReady {
    address public constant VETETU = 0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4;
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant OPS = 0x527a819db1eb0e34426297b03bae11F2f8B3A19E;

    uint internal constant MAX_TIME = 16 weeks;
    uint internal constant WEEK = 1 weeks;
    uint public constant MIN_ALLOWANCE = 1000000000000000000;

    address public operator;
    uint[] public veNFTs;
    mapping(uint => uint) public veNFTtoIdx;
    bool public paused = false;
    
    constructor(address _taskCreator) OpsReady(OPS, _taskCreator) {
      operator = _taskCreator;
    }

    receive() external payable {}

    function setOperator(address newOperator) external returns (bool) {
      require(msg.sender == operator);
      operator = newOperator;
      return true;
    }

    function setPaused(bool _paused) external returns (bool) {
      require(msg.sender == operator);
      paused = _paused;
      return true;
    }

    function rescueToken(address tok, uint amount) external returns (bool){
      require(msg.sender == operator);
      require(tok != VETETU);
      IERC20(tok).transfer(operator, amount);
      return true;
    }

    function register(uint veNFT) external returns (uint idx) {
      // sender must own the NFT
      require(veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT));
      // this contract must be an approved operator of the NFT
      require(veTetu(VETETU).isApprovedOrOwner(address(this), veNFT));
      idx = veNFTs.length;
      veNFTs.push(veNFT);
      refreshIdx(idx);
      return idx;
    }

    function refreshIdx(uint idx) internal{
      veNFTtoIdx[veNFTs[idx]] = idx;
    }

    function unregister(uint veNFT) public returns (bool) {
      uint idx = veNFTtoIdx[veNFT];
      require(veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT));
      veNFTs[idx] = veNFTs[veNFTs.length - 1];
      refreshIdx(idx);
      veNFTs.pop();
      return true;
    }

    function getReadyNFT() public view returns (bool success, uint veNFT) {
      if (paused) {
        return (false, 0);
      }
      address veOwner;
      uint lockEnd;
      uint targetTime = (block.timestamp + MAX_TIME) / WEEK * WEEK;
      uint allowance;

      for(uint i = 0; i < veNFTs.length; i++){
        veNFT = veNFTs[i];
        veOwner = veTetu(VETETU).ownerOf(veNFT);
        lockEnd = veTetu(VETETU).lockedEnd(veNFT);
        allowance = IERC20(WMATIC).allowance(veOwner, address(this));

        if (targetTime > lockEnd && allowance > MIN_ALLOWANCE && veTetu(VETETU).isApprovedOrOwner(address(this), veNFT)) {
          return (true, veNFT);
        }
      }
      return (false, 0);
    }
    
    // for gelato resolver
    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        (bool success, uint veNFT) = getReadyNFT();
        if (!success) {
          return (false, bytes("No veNFTs ready"));
        }

        execPayload = abi.encodeCall(veTetuRelocker.processLock, (veNFT));
        return (true, execPayload);
    }

    function processLock(uint veNFT) external onlyDedicatedMsgSender returns (bool) {
      require(!paused);

      address veOwner = veTetu(VETETU).ownerOf(veNFT);
      (uint256 fee,address feeToken) = _getFeeDetails();
      require(feeToken == ETH || (fee == 0 && feeToken == address(0)));

      IERC20(WMATIC).transferFrom(veOwner, address(this), fee);
      WMatic(WMATIC).withdraw(fee);
      veTetu(VETETU).increaseUnlockTime(veNFT, MAX_TIME);

      if (feeToken != address(0)){
        _transfer(fee,feeToken);
      }
      return true;
    }

}
