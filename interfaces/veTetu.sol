// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "tetu/contracts/interfaces/IVeTetu.sol";

interface veTetu is IVeTetu {
  function increaseUnlockTime(uint _tokenId, uint _lockDuration) external returns (uint power, uint unlockDate);
  function ownerOf(uint _tokenId) external view returns (address);
  function setApprovalForAll(address _operator, bool _approved) external;
  function tokenOfOwnerByIndex(address _owner, uint _tokenIndex) external view returns (uint);
  function ownerToOperators(address _owner, address _operator) external view returns (bool);
  function withdraw(address stakingToken, uint _tokenId) external;
  function withdrawAll(uint _tokenId) external;

  function safeTransferFrom(
    address _from,
    address _to,
    uint _tokenId,
    bytes memory _data
  ) external;
  function safeTransferFrom(
    address _from,
    address _to,
    uint _tokenId
  ) external;
}