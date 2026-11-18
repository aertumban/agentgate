// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Test-only stand-in for the SPACE ID Agent ID registry.
///         NOT deployed to mainnet; used only by the local test suite.
contract MockAgentID {
    mapping(address => uint256) public balanceOf;

    function setHolder(address user, uint256 amount) external {
        balanceOf[user] = amount;
    }
}
