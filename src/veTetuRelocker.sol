

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
  function tokenOfOwnerByIndex(address _owner, uint _tokenIndex) external view returns (uint);
  function ownerToOperators(address _owner, address _operator) external view returns (bool);
}


// simple proxy contract that users can defer relocking capabilities to.
// this is just safety measure to ensure that the operator authority
// can't be abused
contract veTetuRelockerProxy {
  address public constant VETETU = 0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4;
  address public immutable operator;

  constructor(address _operator) { 
    operator = _operator;
  }

  function relock(uint veNFT, uint duration) external returns (bool) {
    require(msg.sender == operator);
    veTetu(VETETU).increaseUnlockTime(veNFT, duration);
    return true;
  }

}


contract veTetuRelocker is OpsReady {
    address public constant VETETU = 0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4;
    address public constant OPS = 0x527a819db1eb0e34426297b03bae11F2f8B3A19E;

    uint internal constant MAX_TIME = 16 weeks;
    uint internal constant WEEK = 1 weeks;
    // minimum balance needed to be queued
    uint public constant MIN_ALLOWANCE = 100000000000000000;
    address public immutable relocker;

    address public operator;
    uint[] public veNFTs;
    mapping(uint => uint) internal _veNFTtoIdx;
    bool public paused = false;
    mapping(uint => uint) public balances;
    mapping(uint => uint) public lockTime;

    constructor(address ops, address _taskCreator) OpsReady(ops, _taskCreator) {
      operator = _taskCreator;
      relocker = address(new veTetuRelockerProxy(address(this)));
    }

    modifier lockerApproved {
      require(veTetu(VETETU).ownerToOperators(msg.sender, relocker), "locker contract is not operator");
      _;
   }

    receive() external lockerApproved payable {
      _depositAll(msg.sender, msg.value);
    }

    function depositAll() external lockerApproved payable {
      _depositAll(msg.sender, msg.value);
    }

    function registerAll() external lockerApproved payable {
      _registerAll(msg.sender, msg.value, MAX_TIME);
    }

    function registerAll(uint _weeks) external lockerApproved payable {
      require(_weeks <= 16);
      _registerAll(msg.sender, msg.value, _weeks * WEEK);
    }

    // returns all veNFTs registered by the user
    function userTokens(address user) public view returns (uint[] memory) {
      uint i = 0;
      uint veNFT;
      uint j = 0;
      do { 
        veNFT = veTetu(VETETU).tokenOfOwnerByIndex(user, i++);
        if (isRegistered(veNFT)) {
          j++;
        }
      } while (veNFT > 0);
      uint[] memory toks = new uint[](j);
      i = 0;
      j = 0;
      do {
        veNFT = veTetu(VETETU).tokenOfOwnerByIndex(user, i++);
        if (isRegistered(veNFT)) {
          toks[j++] = veNFT;
        }
      } while (veNFT > 0);
      return toks;
    }

    function _registerAll(address user, uint value, uint duration) internal {
      uint i = 0;
      uint veNFT;
      bool didRegister = false;
      do { 
        veNFT = veTetu(VETETU).tokenOfOwnerByIndex(user, i++);
        if (_registerCondition(veNFT)){
          _register(veNFT, 0, duration);
          didRegister = true;
        }
      } while (veNFT > 0);
      // need to register at least one token
      require(didRegister);
      if (value > 0) { _depositAll(user, value); }
    }

    function _depositAll(address user, uint value) internal {
      uint[] memory toks = userTokens(user);
      require (toks.length > 0);
      uint perToken = value / toks.length;
      uint i;
      for(i = 0; i < toks.length; i++){
        _addToBalanceFor(toks[i], user, perToken);
      }
    }

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

    function _deposit(uint veNFT, uint amount) internal{
      balances[veNFT] = amount + balances[veNFT];
    }

    function _withdraw(uint veNFT, uint amount) internal{
      balances[veNFT] = balances[veNFT] - amount;
    }

    function register(uint veNFT) external payable returns (uint idx) {
      require(_registerCondition(veNFT));
      return _register(veNFT, msg.value, MAX_TIME);
    }

    function register(uint veNFT, uint _weeks) external payable returns (uint idx) {
      require(_registerCondition(veNFT));
      require (_weeks <= 16);
      return _register(veNFT, msg.value, _weeks * WEEK);
    }

    function _registerCondition(uint veNFT) internal view returns (bool) {
      return veNFT > 0
             && veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT) 
             && veTetu(VETETU).isApprovedOrOwner(relocker, veNFT)
             && !isRegistered(veNFT);
    }

    function _register(uint veNFT, uint value, uint duration) internal returns (uint idx) {
      _deposit(veNFT, value);

      idx = veNFTs.length;
      veNFTs.push(veNFT);
      refreshIdx(idx);
      lockTime[veNFT] = duration;
      return idx;
    }

    function addToBalance(uint veNFT) external payable returns (bool) {
       _addToBalanceFor(veNFT, msg.sender, msg.value);
       return true;
    }

    function addToBalanceFor(uint veNFT, address to) external payable returns (bool) {
      _addToBalanceFor(veNFT, to, msg.value);
      return true;
    }

    function _addToBalanceFor(uint veNFT, address to, uint value) internal {
      // doesn't actually enforce anything, just a sanity check
      require(veTetu(VETETU).isApprovedOrOwner(to, veNFT));
      _deposit(veNFT, value);
      
    }

    function withdrawFromBalance(uint veNFT, uint amount) external returns (bool) {
      require(veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT));
      _withdraw(veNFT, amount);
      payable(msg.sender).transfer(amount);
      return true;
    }

    function setLockTIme(uint veNFT, uint _weeks) external returns (bool) {
      require(veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT));
      require (_weeks <= 16);
      lockTime[veNFT] = _weeks * WEEK;
      return true;
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
      _unregister(veNFT, fee_return);
      return true;
    }

    function _unregister(uint veNFT, address fee_return) internal {
      uint idx = veNFTtoIdx(veNFT);
      veNFTs[idx] = veNFTs[veNFTs.length - 1];
      refreshIdx(idx);
      _veNFTtoIdx[veNFT] = 0;
      veNFTs.pop();

      uint bal = balances[veNFT];
      _withdraw(veNFT, bal);
      payable(fee_return).transfer(bal);
    }

    function unregister(uint veNFT) external returns (bool) {
      return unregister(veNFT, msg.sender);
    }

    function unregisterAll() external returns (bool) {
      return unregisterAll(msg.sender);
    }

    function unregisterAll(address fee_return) public returns (bool) {
      uint i = 0;
      uint veNFT;
      
      do {
        veNFT = veTetu(VETETU).tokenOfOwnerByIndex(msg.sender, i++);
        if(isRegistered(veNFT)){
          _unregister(veNFT, fee_return);
        }
      }
      while (veNFT > 0);
      return true;
    }

    function floor(uint a, uint m) pure internal returns (uint ) {
      return (a / m) * m;
    }

    function getReadyNFT() public view returns (bool success, uint veNFT) {
      if (paused || veNFTs.length == 0) {
        return (false, 0);
      }
      uint lockEnd;
      uint balance;

      // start at an arbitrary point in the list
      // so we can't get stuck
      uint startidx = block.timestamp % veNFTs.length;
      uint i = startidx;

      do {
        veNFT = veNFTs[i];
        lockEnd = veTetu(VETETU).lockedEnd(veNFT);
        balance = balances[veNFT];

        if (   floor(block.timestamp + lockTime[veNFT], WEEK) > lockEnd
            && lockEnd > block.timestamp
            && balance >= MIN_ALLOWANCE 
            && veTetu(VETETU).isApprovedOrOwner(relocker, veNFT)) 
          { return (true, veNFT); }
        i = (i + 1) % veNFTs.length;
        } while(i != startidx);
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
      require(isRegistered(veNFT));

      veTetuRelockerProxy(relocker).relock(veNFT, lockTime[veNFT]);

      (uint256 fee,address feeToken) = _getFeeDetails();
      require(feeToken == ETH);
      _withdraw(veNFT, fee);
      _transfer(fee,feeToken);
      return true;
    }

}
