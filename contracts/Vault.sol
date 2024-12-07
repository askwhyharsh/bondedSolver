// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract LiquidityVault is ERC721, Ownable, ReentrancyGuard {
    // Token pair for this vault
    address public immutable token0;
    address public immutable token1;
    
    struct Position {
        uint256 amount0;
        uint256 amount1;
        uint256 feesClaimed0;
        uint256 feesClaimed1;
    }
    
    // NFT position ID => Position details
    mapping(uint256 => Position) public positions;
    // Next position ID to mint
    uint256 private nextPositionId = 1;
    
    // Total amounts in the vault
    uint256 public totalAmount0;
    uint256 public totalAmount1;
    
    // Accumulated fees per share (scaled by 1e18)
    uint256 public feeGrowthGlobal0;
    uint256 public feeGrowthGlobal1;
    
    // Constants
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public swapFeeRate = 30; // 0.3% default fee

    // Events
    event PositionOpened(address indexed owner, uint256 positionId, uint256 amount0, uint256 amount1);
    event PositionClosed(address indexed owner, uint256 positionId);
    event SwapExecuted(address indexed user, address sellToken, address buyToken, uint256 sellAmount, uint256 buyAmount);
    event FeesCollected(uint256 positionId, uint256 amount0, uint256 amount1);

    constructor(
        address _token0,
        address _token1
    ) ERC721("Liquidity Position", "LP") Ownable(msg.sender) {
        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @notice Opens a new liquidity position
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     * @return positionId The ID of the newly minted position NFT
     */
    function openPosition(uint256 amount0, uint256 amount1) external nonReentrant returns (uint256) {
        require(amount0 > 0 || amount1 > 0, "Must provide liquidity");
        
        // Transfer tokens to vault
        if (amount0 > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        }
        
        // Mint NFT position
        uint256 positionId = nextPositionId++;
        _mint(msg.sender, positionId);
        
        // Create position
        positions[positionId] = Position({
            amount0: amount0,
            amount1: amount1,
            feesClaimed0: 0,
            feesClaimed1: 0
        });
        
        totalAmount0 += amount0;
        totalAmount1 += amount1;
        
        emit PositionOpened(msg.sender, positionId, amount0, amount1);
        return positionId;
    }

    /**
     * @notice Execute swap by authorized solver
     * @dev Only callable by authorized solvers
     */
    function executeSwap(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    ) external nonReentrant {
        // Verify tokens are valid
        require(
            (sellToken == token0 && buyToken == token1) ||
            (sellToken == token1 && buyToken == token0),
            "Invalid token pair"
        );
        
        uint256 feeAmount = (sellAmount* swapFeeRate) / FEE_DENOMINATOR;
        uint256 netSellAmount = sellAmount - feeAmount;
        
        // Update fee growth
        if (sellToken == token0) {
            feeGrowthGlobal0 += (feeAmount * 1e18) / totalAmount0;
        } else {
            feeGrowthGlobal1 += (feeAmount * 1e18) / totalAmount1;
        }
        
        // Execute swap logic here
        // ... implement your swap mechanism ...
        
        emit SwapExecuted(msg.sender, sellToken, buyToken, sellAmount, buyAmount);
    }

    /**
     * @notice Collect accumulated fees for a position
     * @param positionId The ID of the position
     */
    function collectFees(uint256 positionId) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender, positionId), "Not authorized");
        Position storage position = positions[positionId];
        
        // Calculate unclaimed fees
        uint256 fees0 = (position.amount0 * feeGrowthGlobal0 / 1e18) - position.feesClaimed0;
        uint256 fees1 = (position.amount1 * feeGrowthGlobal1 / 1e18) - position.feesClaimed1;
        
        // Update claimed fees
        position.feesClaimed0 += fees0;
        position.feesClaimed1 += fees1;
        
        // Transfer fees
        if (fees0 > 0) IERC20(token0).transfer(msg.sender, fees0);
        if (fees1 > 0) IERC20(token1).transfer(msg.sender, fees1);
        
        emit FeesCollected(positionId, fees0, fees1);
    }

    // ... Add other necessary functions like closePosition, getPositionDetails, etc. ...
}

