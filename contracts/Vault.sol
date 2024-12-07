// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
interface IGPv2Settlement {
    function validateSignature(GPv2Order.Data memory order, bytes memory signature) external view returns (bool);
    function settle(
        IERC20[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2Trade.Data[] calldata trades,
        GPv2Interaction.Data[][3] calldata interactions
    ) external;
}

interface GPv2Order {
    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        bytes32 kind;
        bool partiallyFillable;
        bytes32 sellTokenBalance;
        bytes32 buyTokenBalance;
    }
}

interface GPv2Trade {
    struct Data {
        GPv2Order.Data order;
        bytes signature;
        uint256 executedAmount;
    }
}

interface GPv2Interaction {
    struct Data {
        address target;
        uint256 value;
        bytes callData;
    }
}
/**
 * @title Vault
 * @notice A vault contract that integrates with CoW Protocol for token swaps
 * @dev Uses signed orders from CoW Protocol solvers for executing trades
 */
contract Vault is Ownable, ReentrancyGuard {
    // CoW Protocol settlement contract
    address public immutable settlement;
    
    // Token pair for this vault
    address public immutable token0;
    address public immutable token1;
    
    // Fee collector for swap fees
    address public feeCollector;
    
    // User balances and vault positions
    mapping(address => mapping(address => uint256)) public userBalances;
    
    // Events
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event SwapExecuted(
        address indexed user,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    );
    event FeeCollected(address indexed token, uint256 amount);
    event FeeRateUpdated(uint256 newRate);
    event FeeCollectorUpdated(address newCollector);
    event WithdrawFees(address indexed token, uint256 amount);

    // Add new state variables
    uint256 public constant FEE_DENOMINATOR = 10000; // Base for fee calculation (100% = 10000)
    uint256 public swapFeeRate = 30; // 0.3% default fee
    
    constructor(
        address _settlement,
        address _token0,
        address _token1,
        address _feeCollector
    ) ReentrancyGuard() Ownable(msg.sender) {
        settlement = _settlement;
        token0 = _token0;
        token1 = _token1;
        feeCollector = _feeCollector;
    }

    /**
     * @notice Deposits tokens into the vault
     * @param token The token to deposit (must be token0 or token1)
     * @param amount Amount to deposit
     */
    function deposit(address token, uint256 amount) external nonReentrant {
        require(token == token0 || token == token1, "Invalid token");
        require(amount > 0, "Amount must be > 0");
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        userBalances[msg.sender][token] += amount;
        
        emit Deposit(msg.sender, token, amount);
    }

    /**
     * @notice Executes a swap based on solver's signed price
     * @param sellToken Token to sell
     * @param buyToken Token to buy
     * @param sellAmount Amount to sell
     * @param minBuyAmount Minimum amount to receive
     * @param signature Solver's signature validating the price
     */
    function executeSwap(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        bytes calldata signature
    ) external nonReentrant {
        // Verify tokens are valid
        require(
            (sellToken == token0 && buyToken == token1) ||
            (sellToken == token1 && buyToken == token0),
            "Invalid token pair"
        );
        
        // Verify user has enough balance
        require(userBalances[msg.sender][sellToken] >= sellAmount, "Insufficient balance");
        
        // Calculate and deduct fee
        uint256 feeAmount = calculateFee(sellAmount);
        uint256 netSellAmount = sellAmount - feeAmount;
        
        // Update user's sell token balance
        userBalances[msg.sender][sellToken] -= sellAmount;
        // Add fee to vault's balance
        userBalances[address(this)][sellToken] += feeAmount;
        
        // Create GPv2Order.Data struct for CoW Protocol
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: address(this), // Vault receives tokens
            sellAmount: netSellAmount,
            buyAmount: minBuyAmount,
            validTo: uint32(block.timestamp + 900), // 15 minutes validity
            appData: bytes32(0),
            feeAmount: 0, // Protocol fees handled separately
            kind: bytes32("sell"),
            partiallyFillable: false,
            sellTokenBalance: bytes32("erc20"),
            buyTokenBalance: bytes32("erc20")
        });
        
        // Verify solver signature and execute trade
        require(IGPv2Settlement(settlement).validateSignature(order, signature), "Invalid signature");
        
        // Create trades array
        GPv2Trade.Data[] memory trades = new GPv2Trade.Data[](1);
        trades[0] = GPv2Trade.Data({
            order: order,
            signature: signature,
            executedAmount: netSellAmount
        });
        
        // Create dynamic arrays for tokens and prices
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(sellToken);
        tokens[1] = IERC20(buyToken);
        
        uint256[] memory prices = new uint256[](2);
        prices[0] = netSellAmount;
        prices[1] = minBuyAmount;

        // Create empty interactions array
        GPv2Interaction.Data[][3] memory interactions;
        for(uint i = 0; i < 3; i++) {
            interactions[i] = new GPv2Interaction.Data[](0);
        }
        
        IGPv2Settlement(settlement).settle(
            tokens,
            prices,
            trades,
            interactions
        );

        // Update user's buy token balance with actual received amount
        uint256 receivedAmount = IERC20(buyToken).balanceOf(address(this));
        userBalances[msg.sender][buyToken] += receivedAmount;
        
        emit SwapExecuted(msg.sender, sellToken, buyToken, sellAmount, receivedAmount);
    }

    /**
     * @notice Withdraws tokens from the vault
     * @param token The token to withdraw (must be token0 or token1)
     * @param amount Amount to withdraw
     */
    function withdraw(address token, uint256 amount) external nonReentrant {
        require(token == token0 || token == token1, "Invalid token");
        require(amount > 0, "Amount must be > 0");
        require(userBalances[msg.sender][token] >= amount, "Insufficient balance");
        
        userBalances[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, token, amount);
    }

    /**
     * @notice Get user balance for a specific token
     * @param user Address of the user
     * @param token Address of the token
     * @return balance User's balance of the specified token
     */
    function getBalance(address user, address token) external view returns (uint256) {
        require(token == token0 || token == token1, "Invalid token");
        return userBalances[user][token];
    }

    /**
     * @notice Update the swap fee rate
     * @param newFeeRate New fee rate (base 10000, e.g., 30 = 0.3%)
     */
    function updateFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= 100, "Fee rate too high"); // Max 1%
        swapFeeRate = newFeeRate;
        emit FeeRateUpdated(newFeeRate);
    }

    /**
     * @notice Update the fee collector address
     * @param newFeeCollector New fee collector address
     */
    function updateFeeCollector(address newFeeCollector) external onlyOwner {
        require(newFeeCollector != address(0), "Invalid address");
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }

    /**
     * @notice Calculate fee amount for a given trade amount
     * @param amount Amount to calculate fee for
     * @return Fee amount
     */
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * swapFeeRate) / FEE_DENOMINATOR;
    }

    /**
     * @notice Collect accumulated fees for a specific token
     * @param token Token to collect fees for
     */
    function collectFees(address token) external nonReentrant {
        require(msg.sender == feeCollector, "Only fee collector");
        require(token == token0 || token == token1, "Invalid token");
        
        uint256 feeBalance = userBalances[address(this)][token];
        require(feeBalance > 0, "No fees to collect");
        
        userBalances[address(this)][token] = 0;
        IERC20(token).transfer(feeCollector, feeBalance);
        
        emit FeeCollected(token, feeBalance);
    }

    /**
     * @notice Get total vault balance for a specific token
     * @param token Token address to check
     * @return Total balance held by the vault
     */
    function getTotalBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Get accumulated fees for a specific token
     * @param token Token to check fees for
     * @return Accumulated fees
     */
    function getAccumulatedFees(address token) external view returns (uint256) {
        return userBalances[address(this)][token];
    }

    /**
     * @notice Emergency withdraw function for stuck tokens
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token == token0 || token == token1, "Invalid token");
        IERC20(token).transfer(owner(), amount);
    }
}

