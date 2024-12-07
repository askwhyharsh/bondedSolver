// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./Vault2.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VaultFactory
 * @notice Factory contract for deploying Vault2 instances
 * @dev Creates and tracks Vault2 contracts for different token pairs
 */
contract VaultFactory is Ownable {
    // Mapping from token pair to vault address
    mapping(address => mapping(address => address)) public getVault;
    // Array to store all created vaults
    address[] public allVaults;
    
    event VaultCreated(
        address indexed token0,
        address indexed token1,
        address vault,
        uint256 vaultId
    );

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Creates a new Vault2 instance for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return vault Address of the created vault
     */
    function createVault(address tokenA, address tokenB) external returns (address vault) {
        require(tokenA != tokenB, "VF: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "VF: ZERO_ADDRESS");

        // Sort token addresses
        (address token0, address token1) = tokenA < tokenB 
            ? (tokenA, tokenB) 
            : (tokenB, tokenA);

        require(getVault[token0][token1] == address(0), "VF: VAULT_EXISTS");

        // Deploy new Vault2
        vault = address(new Vault2(token0, token1));
        
        // Store vault address
        getVault[token0][token1] = vault;
        getVault[token1][token0] = vault; // populate reverse mapping
        allVaults.push(vault);

        emit VaultCreated(
            token0,
            token1,
            vault,
            allVaults.length - 1
        );
    }

    /**
     * @notice Returns the number of vaults created
     */
    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }

    /**
     * @notice Transfers ownership of a vault to a new address
     * @param vault Address of the vault
     * @param newOwner Address of the new owner
     */
    function transferVaultOwnership(address vault, address newOwner) external onlyOwner {
        Vault2(vault).transferOwnership(newOwner);
    }
}
