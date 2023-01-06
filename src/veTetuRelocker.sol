

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
    mapping(uint => uint) internal _veNFTtoIdx;
    bool public paused = false;
    mapping(uint => uint) public coolDown;
    
    constructor(address ops, address _taskCreator) OpsReady(ops, _taskCreator) {
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


    function getExcessMatic() external returns (bool) {
      require(msg.sender == operator);
      uint expected = veNFTs.length * MIN_ALLOWANCE;
      payable(operator).transfer(address(this).balance - expected);
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
      // ensure we have enough MATIC to unregister this user if they ever
      // fail to be processed
      IERC20(WMATIC).transferFrom(msg.sender, address(this), MIN_ALLOWANCE);
      WMatic(WMATIC).withdraw(MIN_ALLOWANCE);
      return idx;
    }

    function isRegistered(uint veNFT) public view returns (bool) {
      uint idx = _veNFTtoIdx[veNFT];
      return (idx > 0);
    }

    function veNFTtoIdx(uint veNFT) public view returns (uint) {
      uint idx = _veNFTtoIdx[veNFT];
      require(idx > 0);
      return (idx-1);
    }

    function refreshIdx(uint idx) internal{
      _veNFTtoIdx[veNFTs[idx]] = (idx + 1);
    }



    function unregister(uint veNFT, address fee_return) public  returns (bool) { 
      require(veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT));
      _unregister(veNFT);
      // pay back register deposit
      payable(fee_return).transfer(MIN_ALLOWANCE);
      return true;
    }

    function unregister(uint veNFT) external returns (bool) {
      return unregister(veNFT, msg.sender);
    }

    function _unregister(uint veNFT) internal returns (bool) {
      uint idx = veNFTtoIdx(veNFT);
      veNFTs[idx] = veNFTs[veNFTs.length - 1];
      refreshIdx(idx);
      _veNFTtoIdx[veNFT] = 0;
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
      uint balance;

      for(uint i = 0; i < veNFTs.length; i++){
        veNFT = veNFTs[i];
        veOwner = veTetu(VETETU).ownerOf(veNFT);
        lockEnd = veTetu(VETETU).lockedEnd(veNFT);
        allowance = IERC20(WMATIC).allowance(veOwner, address(this));
        balance = IERC20(WMATIC).balanceOf(veOwner);

        if (targetTime > lockEnd && allowance > MIN_ALLOWANCE && balance >= MIN_ALLOWANCE && veTetu(VETETU).isApprovedOrOwner(address(this), veNFT) && isOffCooldown(veNFT)) {
          return (true, veNFT);
        }
      }
      return (false, 0);
    }

    function isOffCooldown(uint veNFT) public view returns (bool) {
      return (coolDown[veNFT] == 0 || coolDown[veNFT] >= block.timestamp);
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
      require(isRegistered(veNFT));
      
      (uint256 fee,address feeToken) = _getFeeDetails();
      require(feeToken == ETH);
      address veOwner = veTetu(VETETU).ownerOf(veNFT);

      try IERC20(WMATIC).transferFrom(veOwner, address(this), fee) { } catch {
        // failed to retrieve the required fees from the owner, so we unregister them
        // using their initial deposit
        require (fee <= MIN_ALLOWANCE);
        (payable(veOwner).send(MIN_ALLOWANCE - fee));
        _unregister(veNFT);
        _transfer(fee,feeToken);
        return true;
      }
      WMatic(WMATIC).withdraw(fee);

      // if this contract is no longer an approved operator, then
      // we just unregister the NFT (paying back the user their deposit, since the 
      // transaction fee was paid)
      
      if (!veTetu(VETETU).isApprovedOrOwner(address(this), veNFT)) {
        (payable(veOwner).send(MIN_ALLOWANCE));
        _unregister(veNFT);
        _transfer(fee,feeToken);
        return true;
      }

      try veTetu(VETETU).increaseUnlockTime(veNFT, MAX_TIME) { } catch {
          // if increasing the unlock fails, try again in a day
          // in practice this shouldn't happen, but it's technically
          // possible
          coolDown[veNFT] = block.timestamp + 1 days;
        }
      _transfer(fee,feeToken);
      return true;
    }

}
