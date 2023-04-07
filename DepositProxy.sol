// SPDX-License-Identifier: MIT

pragma solidity >= 0.8.0;

import "./DepositStorage.sol";

contract DepositProxy is DepositStorage{
    constructor(address _implementation){
        admin = msg.sender;
        implementation = _implementation;
        rate = 20000;
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
