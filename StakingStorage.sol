// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

contract StakingStorage {
    struct MainNodeInfo {
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 totalStakeAmount;
        uint256 totalRewardAmount;
        uint256 totalLightNodes;
        uint256 rate;            // rate for APR base is 10000
        uint256 commissionRate;  // commission rate of main node 
        bool isStopped;
        bool isUsed;
    }

    struct LightNodeInfo {
        uint256 mainNodeId;
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 totalStakeAmount;
        uint256 totalRewardAmount;
        uint256 totalUsers;
        uint256 registerTime;
        uint256 commissionRate;
        address ownerAddress;
        bool isStopped;
        bool isUsed;
    }

    struct StakeInfo {
        uint256 lightNodeId;
        uint256 updateTime;
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 totalStakeAmount;
        uint256 totalRewardAmount;
        uint256 unstakeCount;
        address referee; 
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
    mapping (uint256 => MainNodeInfo) public mainNodeInfo;  // node id -> info
    mapping (uint256 => LightNodeInfo) public lightNodeInfo; // node id -> info
    mapping (address => uint256) public ownerLightNodeId; // owner address -> node id
    mapping (address => StakeInfo) public stakeInfo; // address -> stake info
    mapping (address => uint256) public referRewards; // address -> refer award 
    mapping (address => bool) public lightNodeBlacklist; // address -> refer award 
    mapping (uint256 => mapping(address => uint256)) public dynamicReward; // date -> (address -> award) 
    mapping (address => uint256) public firstDynamicRecord; // address -> date 
    mapping (address => uint256) public dynamicRewardClaimed; // address -> amount claimed
    mapping(address => UnstakeInfo[]) public unstakeInfo; // user -> unstakeInfo 

    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;  // seconds per day
    uint256 constant DEFAULT_RATE = 10000;  // default APR rate 
    uint256 public currentTotalStaked;  // current total staked in the contract
    uint256 public currentTotalReward;  // current total reward available for claiming
    uint256 public totalStaked;     // total staked amount (including unstaked)
    uint256 public totalReward;     // total reward generated (inlcuding claimed)
    uint256 public totalUnstaked;   // total unstaked 
    uint256 public totalRewardClaimed; // total reward claimed
    uint256 public stopLimit; // stop limit of light node 

    uint256 public mainNodeCap;     // staking cap for every main node  
    uint256 public currentMainNodeIndex; // start from 1
    uint256 public currentLightNodeIndex; // start from 1
    uint256 public initTime; // init time for staking 
}
