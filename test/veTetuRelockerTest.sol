// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "../src/veTetuRelocker.sol";
import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";

contract veTetuRelockerTest is Test {
    uint256 constant FORK_BLOCK_NUMBER = 37680341;
    string MATIC_RPC_URL = vm.envString("MATIC_RPC_URL");

    address public constant VETETU = 0x6FB29DD17fa6E27BD112Bc3A2D0b8dae597AeDA4;
    address public constant USER = 0xa68444587ea4D3460BBc11d5aeBc1c817518d648;
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    uint constant WEEK = 1 weeks;

    function testLockerLogic() public {
        uint veNFT = 96;

        vm.createSelectFork(MATIC_RPC_URL, FORK_BLOCK_NUMBER);
        veTetuRelocker c = new veTetuRelocker(USER);

        vm.startPrank(USER);
        veTetu(VETETU).increaseUnlockTime(veNFT, 16 weeks);
        vm.warp(block.timestamp + 7 days);

        veTetu(VETETU).setApprovalForAll(address(c), true);
        IERC20(WMATIC).approve(address(c), type(uint256).max);
        // get some WMATIC for fees
        uint sendAmount = 100000000000000000;
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
        vm.startPrank(USER);

    }
}