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
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;


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
        veTetu(VETETU).setApprovalForAll(address(c), true);
        uint sendAmount = c.MIN_ALLOWANCE() * 2;
        (bool s,) = payable(WMATIC).call{value: sendAmount}("");
        require (s);
        IERC20(WMATIC).approve(address(c), type(uint256).max);
        c.register(veNFT);

        c.unregister(veNFT);



    }

    // testing failure od
    function testFModes() public {
        uint veNFT = 96;
        vm.createSelectFork(MATIC_RPC_URL, FORK_BLOCK_NUMBER);
        veTetuRelocker c = mkRelocker();

        vm.startPrank(USER);
        veTetu(VETETU).setApprovalForAll(address(c), true);
        IERC20(WMATIC).approve(address(c), type(uint256).max);
        uint sendAmount = c.MIN_ALLOWANCE();
        (bool s,) = payable(WMATIC).call{value: sendAmount}("");
        require (s);

        
        c.register(veNFT);
        vm.stopPrank();

        vm.startPrank(c.dedicatedMsgSender());

        // deregisters, since we can't pay the fees
        c.processLock(veNFT);
        require (!c.isRegistered(veNFT));

        (bool canExec,) = c.checker();
        require(!canExec);
        vm.stopPrank();

        vm.startPrank(USER);
        (bool s2,) = payable(WMATIC).call{value: (sendAmount * 3)}("");
        require (s2);
        c.register(veNFT);

        veTetu(VETETU).increaseUnlockTime(veNFT, 16 weeks);

        vm.stopPrank();
        vm.startPrank(c.dedicatedMsgSender());
        // sets cooldown, since the lock increase will fail
        c.processLock(veNFT);
        require (c.coolDown(veNFT) == block.timestamp + 1 days);
        // on cooldown
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

        veTetu(VETETU).setApprovalForAll(address(c), true);
        IERC20(WMATIC).approve(address(c), type(uint256).max);
        // get some WMATIC for fees
        uint sendAmount = c.MIN_ALLOWANCE() * 3;
        (bool s,) = payable(WMATIC).call{value: sendAmount}("");
        require (s);
        c.register(veNFT);
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