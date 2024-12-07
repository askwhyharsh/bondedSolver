// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "../Vault.sol";

contract MockGPv2Settlement {
    uint256 public totalSellAmount;
    function validateSignature(GPv2Order.Data memory, bytes memory) external pure returns (bool) {
        return true;
    }

    function settle(
        IERC20[] calldata,
        uint256[] calldata,
        GPv2Trade.Data[] calldata,
        GPv2Interaction.Data[][3] calldata
    ) external {
        // Mock implementation
        totalSellAmount += 1;
    }
}