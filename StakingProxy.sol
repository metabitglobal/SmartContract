// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import "./StakingStorage.sol";

contract StakingProxy is StakingStorage {
    constructor(address _implementation){
        admin = msg.sender;
        operator = 0xB6c5b59374763ea232BC7cd7F25A650b063E3368;
        implementation = _implementation;
        currentMainNodeIndex = 1;
        currentLightNodeIndex = 1;
        stopLimit = 1000;
        mainNodeCap = 8_500_000* 1 ether;
        initTime = 1680278400; // since April 1st
    }

    receive() external payable {}

    fallback() external payable {
        (bool success, bytes memory data) = implementation.delegatecall(msg.data);
        if (!success) {
            _revertWithData(data);
        }
        _returnWithData(data);
    }

    /// @dev Revert with arbitrary bytes.
    /// @param data Revert data.
    function _revertWithData(bytes memory data) private pure {
        assembly { revert(add(data, 32), mload(data)) }
    }

    /// @dev Return with arbitrary bytes.
    /// @param data Return data.
    function _returnWithData(bytes memory data) private pure {
        assembly { return(add(data, 32), mload(data)) }
    }
}
