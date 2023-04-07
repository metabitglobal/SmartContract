// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

contract DepositStorage {
    struct DepositInfo {
        address user;
        uint256 updateTime;
        uint256 depositAmount;
        uint256 ratePerSec; //decimal is 18
        bool isUsed;
    }

    struct UnstakeInfo {
        uint256 timestamp;
        uint256 amount;
        bool isClaimed;
        bool isUsed;
    }

    address public implementation;
    address public admin;
    uint256 public totalDeposit;
    uint256 public totalWithdraw;
    uint256 public totalReward;
    uint256 public rate;

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public deposits;
    mapping(address => DepositInfo) public rateinfo;
    mapping(address => UnstakeInfo[]) public unstakeInfo; // user -> unstakeInfo 
}
