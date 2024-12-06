// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract Vault {
    // create vault, vault is created between a token pair and a yield bearing token or an nft is issued against it
    // swap — function to swap 2 tokens based on signed price sent by the solver
    // fee collector — fee from swaps are stored here
    address public token0;
    address public token1;
    address public yieldToken;
    constructor(address _token0, address _token1, address _yieldToken) {
        token0 = _token0;
        token1 = _token1;
        yieldToken = _yieldToken;
    }
    // create vault
    function createVault() public {
        // create vault
    }
}

