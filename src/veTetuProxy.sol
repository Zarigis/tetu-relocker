

// SPDX-License-Identifier: MIT


pragma solidity ^0.8.13;

import "../interfaces/veTetu.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

// Contract for conferring fine-grained authority to veTetu operators
contract veTetuProxy {
  address public constant VETETU = 0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4;
  // contract -> NFT -> caller -> auth
  mapping (address => mapping (uint => mapping(address => uint8))) public authMap;

  uint8 constant TRANSFER = 1;
  uint8 constant WITHDRAW = 2;
  uint8 constant LOCK = 4;
  uint8 constant ALL = 255;

  constructor() { }

  function setAuth(address _contract, uint veNFT, address _caller, uint8 auth) internal{
    authMap[_contract][veNFT][_caller] = authMap[_contract][veNFT][_caller] | auth;
  }

  function revokeAuth(address _contract, uint veNFT, address _caller, uint8 auth) internal{
    authMap[_contract][veNFT][_caller] = authMap[_contract][veNFT][_caller] & flip(auth);
  }

  function hasAuth(uint8 _base, uint8 _test) internal pure returns (bool){
    return (_base & _test) > 0;
  }

  function checkAuth(uint8 _base, address _contract, address _caller, uint veNFT) internal view returns (bool) {
    uint8 auth = authMap[_contract][veNFT][_caller];
    if (hasAuth(_base, auth)) {
      return true;
    } else {
      uint8 authAny = authMap[_contract][veNFT][address(0)];
      return hasAuth(_base, authAny);
    }
  }

  function flip(uint8 _b) internal pure returns (uint8) {
    return _b ^ 255;
  }

  function grantAuthority(address _contract, address _caller, uint veNFT, uint8 auth) public {
    require(auth > 0, "cannot grant no authority"); 
    require(veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT), "veNFT not owned");
    require(veTetu(VETETU).isApprovedOrOwner(address(this), veNFT), "veNFT not granted");
    setAuth(_contract, veNFT, _caller, auth);
  }

  function grantAuthorityForAll(address _contract, uint veNFT, uint8 auth) external {
    grantAuthority(_contract, address(0), veNFT, auth);
  }
  
  function revokeAuthority(address _contract, address _caller, uint veNFT, uint8 auth) public {
    require(auth > 0, "cannot revoke no authority"); 
    require(veTetu(VETETU).isApprovedOrOwner(msg.sender, veNFT), "veNFT not owned");
    revokeAuth(_contract, veNFT, _caller, auth);
  }

  // revokes any granted universal authority
  // note that individual addresses may still have authorizations
  function revokeAuthorityForAll(address _contract, uint veNFT, uint8 auth) external {
    revokeAuthority(_contract, address(0), veNFT, auth);
  }

  function increaseUnlockTime(address caller, uint veNFT, uint duration) external returns (uint power, uint unlockDate) {
    require(checkAuth(LOCK, msg.sender, caller, veNFT));
    return veTetu(VETETU).increaseUnlockTime(veNFT, duration);
  }

  function safeTransferFrom(
    address _from,
    address _to,
    uint _tokenId,
    bytes memory _data
  ) external {
    require(checkAuth(TRANSFER, msg.sender, _to, _tokenId));
    veTetu(VETETU).safeTransferFrom(_from, _to, _tokenId, _data);
  }

  function safeTransferFrom(
    address _from,
    address _to,
    uint _tokenId
  ) external {
    require(checkAuth(TRANSFER, msg.sender, _to, _tokenId));
    veTetu(VETETU).safeTransferFrom(_from, _to, _tokenId);
  }

  function withdraw(address _to, address stakingToken, uint _tokenId) external {
    require(checkAuth(WITHDRAW, msg.sender, _to, _tokenId));
    uint startBalance = IERC20(stakingToken).balanceOf(address(this));
    veTetu(VETETU).withdraw(stakingToken, _tokenId);
    IERC20(stakingToken).transfer(_to, IERC20(stakingToken).balanceOf(address(this)) - startBalance);
  }

}