// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../lib/ops/contracts/integrations/Types.sol";
import "../src/veTetuRelocker.sol";
import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";


contract FakeOps {
    
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant OPS = 0x527a819db1eb0e34426297b03bae11F2f8B3A19E;

    constructor () { }

    function gelato() external view returns (address payable) {
        return IOps(OPS).gelato();
    }
    function getFeeDetails() external view returns (uint256, address) {
        return (1, ETH);
    }
}

contract veTetuRelockerTest is Test {
    uint256 constant FORK_BLOCK_NUMBER = 37680341;
    string MATIC_RPC_URL = vm.envString("MATIC_RPC_URL");

    address public constant VETETU = 0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4;
    address public constant USER = 0xa68444587ea4D3460BBc11d5aeBc1c817518d648;

    address public constant OPS = 0x527a819db1eb0e34426297b03bae11F2f8B3A19E;

    uint constant WEEK = 1 weeks;

    function mkRelocker() internal returns (veTetuRelocker) {
        FakeOps ops = new FakeOps();
        veTetuRelocker c = new veTetuRelocker(address(ops), USER);
        return c;
    }

    function testAddRemove() public {
        uint veNFT = 96;
        vm.createSelectFork(MATIC_RPC_URL, FORK_BLOCK_NUMBER);
        veTetuRelocker c = mkRelocker();

        vm.startPrank(USER);
        uint startbalance = payable(USER).balance;
        veTetu(VETETU).setApprovalForAll(c.relocker(), true);
        uint sendAmount = c.DEFAULT_DEPOSIT() * 2;
        c.register{value: sendAmount}(veNFT);
        c.unregister(veNFT);
        require(startbalance == payable(USER).balance);

        (bool b, ) = payable(c).call{value : sendAmount}("");
        require (b);
        require(c.balances(veNFT) == sendAmount);
        require(payable(USER).balance == (startbalance - sendAmount));
        
    }

    // testing failure od
    function testFModes() public {
        uint veNFT = 96;
        vm.createSelectFork(MATIC_RPC_URL, FORK_BLOCK_NUMBER);
        veTetuRelocker c = mkRelocker();

        vm.startPrank(USER);
        veTetu(VETETU).setApprovalForAll(c.relocker(), true);
        uint sendAmount = c.DEFAULT_DEPOSIT();
        
        c.register{value: (sendAmount * 3)}(veNFT);

        veTetu(VETETU).increaseUnlockTime(veNFT, 16 weeks);

        vm.stopPrank();
        vm.startPrank(c.dedicatedMsgSender());
        // sets cooldown, since the lock increase will fail

        (bool b, ) = address(c).call(abi.encodeCall(c.processLock, (veNFT)));
        // fail to process lock
        require (!b);
        (bool canExec2,) = c.checker();
        require(!canExec2);
        vm.warp(block.timestamp + 1 days);
        (bool canExec3,  bytes memory payLoad3) = c.checker();
        require(canExec3);

        (bool s3, ) = address(c).call(payLoad3);
        require (s3);
    }

    function testLockerLogic() public {
        uint veNFT = 96;

        vm.createSelectFork(MATIC_RPC_URL, FORK_BLOCK_NUMBER);
        veTetuRelocker c = mkRelocker();

        vm.startPrank(USER);
        veTetu(VETETU).increaseUnlockTime(veNFT, 16 weeks);
        vm.warp(block.timestamp + 7 days);

        veTetu(VETETU).setApprovalForAll(c.relocker(), true);
        // get some WMATIC for fees
        uint sendAmount = c.DEFAULT_DEPOSIT() * 3;
        c.register{value: sendAmount}(veNFT);
        vm.stopPrank();

        vm.startPrank(c.dedicatedMsgSender());
        
        vm.warp(block.timestamp + 7 days);

        (bool canExec, bytes memory payLoad) = c.checker();
        require (canExec);
        (bool ss, ) = address(c).call(payLoad);
        require (ss);

        uint max_time = (block.timestamp + 16 weeks) / WEEK * WEEK;
        require (veTetu(VETETU).lockedEnd(veNFT) == max_time);

        (bool canExec2, ) = c.checker();
        require (!canExec2);

        vm.warp(block.timestamp + 7 days);

        (bool canExec3, bytes memory payLoad3) = c.checker();
        require (canExec3);

        (bool s3, ) = address(c).call(payLoad3);
        require (s3);
        
        vm.stopPrank();
    }
}