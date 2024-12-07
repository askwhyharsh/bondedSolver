// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
 * @title Vault2
 * @notice A vault contract that manages liquidity positions for token pairs
 * @dev Issues NFTs to represent liquidity positions and distributes fees to position holders
 */
contract Vault2 is ERC721, Ownable, ReentrancyGuard {
    // Token pair for this vault
    address public immutable token0;
    address public immutable token1;
    
    struct Position {
        uint256 amount0;        // Amount of token0 in position
        uint256 amount1;        // Amount of token1 in position
        uint256 feesClaimed0;   // Accumulated fees claimed for token0
        uint256 feesClaimed1;   // Accumulated fees claimed for token1
        uint256 entryFeeGrowthGlobal0;  // Snapshot of global fees when position was created/modified
        uint256 entryFeeGrowthGlobal1;  // Snapshot of global fees when position was created/modified
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
    
    // Fee configuration
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public swapFeeRate = 30; // 0.3% default fee
    
    // Events
    event PositionOpened(
        address indexed owner,
        uint256 indexed positionId,
        uint256 amount0,
        uint256 amount1
    );
    event PositionClosed(
        address indexed owner,
        uint256 indexed positionId,
        uint256 amount0,
        uint256 amount1
    );
    event PositionModified(
        uint256 indexed positionId,
        uint256 addedAmount0,
        uint256 addedAmount1
    );
    event SwapExecuted(
        address indexed user,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint256 feeAmount
    );
    event FeesCollected(
        uint256 indexed positionId,
        uint256 amount0,
        uint256 amount1
    );
    event FeeRateUpdated(uint256 newRate);

    constructor(
        address _token0,
        address _token1
    ) ERC721("Liquidity Position V2", "LPV2") Ownable(msg.sender) {
        require(_token0 != address(0) && _token1 != address(0), "Invalid tokens");
        require(_token0 < _token1, "Token addresses must be sorted");
        token0 = _token0;
        token1 = _token1;
    }

    /**
     * @notice Opens a new liquidity position
     * @param amount0 Amount of token0 to deposit
     * @param amount1 Amount of token1 to deposit
     * @return positionId The ID of the newly minted position NFT
     */
    function openPosition(
        uint256 amount0,
        uint256 amount1
    ) external nonReentrant returns (uint256) {
        require(amount0 > 0 || amount1 > 0, "Must provide liquidity");
        
        uint256 positionId = nextPositionId++;
        
        // Transfer tokens to vault
        if (amount0 > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        }
        
        // Create position
        positions[positionId] = Position({
            amount0: amount0,
            amount1: amount1,
            feesClaimed0: 0,
            feesClaimed1: 0,
            entryFeeGrowthGlobal0: feeGrowthGlobal0,
            entryFeeGrowthGlobal1: feeGrowthGlobal1
        });
        
        // Update totals
        totalAmount0 += amount0;
        totalAmount1 += amount1;
        
        // Mint NFT
        _mint(msg.sender, positionId);
        
        emit PositionOpened(msg.sender, positionId, amount0, amount1);
        return positionId;
    }

    /**
     * @notice Execute swap with provided parameters
     * @param sellToken Token to sell (must be token0 or token1)
     * @param buyToken Token to buy (must be token0 or token1)
     * @param sellAmount Amount of tokens to sell
     * @param minBuyAmount Minimum amount of tokens to receive
     */
    function executeSwap(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        bytes memory signature
    ) external nonReentrant {
        require(
            (sellToken == token0 && buyToken == token1) ||
            (sellToken == token1 && buyToken == token0),
            "Invalid token pair"
        );

        // Create and verify order
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: msg.sender,
            sellAmount: sellAmount,
            buyAmount: minBuyAmount,
            validTo: uint32(block.timestamp + 1 hours), // Example validity period
            appData: bytes32(0),
            feeAmount: 0,
            kind: bytes32(0),
            partiallyFillable: false,
            sellTokenBalance: bytes32(0),
            buyTokenBalance: bytes32(0)
        });
        // verify signature
        require(verifySignature(order, signature), "Invalid signature");

        
        uint256 feeAmount = (sellAmount * swapFeeRate) / FEE_DENOMINATOR;
        uint256 netSellAmount = sellAmount - feeAmount;
        
        // Calculate buy amount based on constant product formula
        uint256 buyAmount;
        if (sellToken == token0) {
            buyAmount = calculateBuyAmount(netSellAmount, totalAmount0, totalAmount1);
            require(buyAmount >= minBuyAmount, "Insufficient output amount");
            
            feeGrowthGlobal0 += (feeAmount * 1e18) / totalAmount0;
            totalAmount0 += sellAmount;
            totalAmount1 -= buyAmount;
        } else {
            buyAmount = calculateBuyAmount(netSellAmount, totalAmount1, totalAmount0);
            require(buyAmount >= minBuyAmount, "Insufficient output amount");
            
            feeGrowthGlobal1 += (feeAmount * 1e18) / totalAmount1;
            totalAmount1 += sellAmount;
            totalAmount0 -= buyAmount;
        }
        
        // Transfer tokens
        IERC20(sellToken).transferFrom(msg.sender, address(this), sellAmount);
        IERC20(buyToken).transfer(msg.sender, buyAmount);
        
        emit SwapExecuted(msg.sender, sellToken, buyToken, sellAmount, buyAmount, feeAmount);
    }

       function verifySignature(GPv2Order.Data memory order, bytes memory signature) internal view returns (bool) {
        // Hash the order data
        bytes32 orderHash = keccak256(abi.encode(
            order.sellToken,
            order.buyToken,
            order.receiver,
            order.sellAmount,
            order.buyAmount,
            order.validTo,
            order.appData,
            order.feeAmount,
            order.kind,
            order.partiallyFillable,
            order.sellTokenBalance,
            order.buyTokenBalance
        ));

        // Hash the message according to EIP-712
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            orderHash
        ));

        // Recover the signer
        address signer = recoverSigner(messageHash, signature);

        // Verify the signer is the sender
        return signer == msg.sender;
    }

       function recoverSigner(bytes32 messageHash, bytes memory signature) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature v value");

        return ecrecover(messageHash, v, r, s);
    }


    /**
     * @notice Calculate buy amount based on constant product formula
     */
    function calculateBuyAmount(
        uint256 sellAmount,
        uint256 sellReserve,
        uint256 buyReserve
    ) internal pure returns (uint256) {
        uint256 numerator = sellAmount * buyReserve;
        uint256 denominator = sellReserve + sellAmount;
        return numerator / denominator;
    }

    /**
     * @notice Collect accumulated fees for a position
     * @param positionId The ID of the position
     */
    function collectFees(uint256 positionId) internal nonReentrant {
        require(_isApprovedOrOwner(msg.sender, positionId), "Not authorized");
        Position storage position = positions[positionId];
        
        // Calculate unclaimed fees
        uint256 unclaimedFees0 = calculateUnclaimedFees(
            position.amount0,
            position.entryFeeGrowthGlobal0,
            feeGrowthGlobal0,
            position.feesClaimed0
        );
        
        uint256 unclaimedFees1 = calculateUnclaimedFees(
            position.amount1,
            position.entryFeeGrowthGlobal1,
            feeGrowthGlobal1,
            position.feesClaimed1
        );
        
        // Update claimed fees
        position.feesClaimed0 += unclaimedFees0;
        position.feesClaimed1 += unclaimedFees1;
        position.entryFeeGrowthGlobal0 = feeGrowthGlobal0;
        position.entryFeeGrowthGlobal1 = feeGrowthGlobal1;
        
        // Transfer fees
        if (unclaimedFees0 > 0) IERC20(token0).transfer(msg.sender, unclaimedFees0);
        if (unclaimedFees1 > 0) IERC20(token1).transfer(msg.sender, unclaimedFees1);
        
        emit FeesCollected(positionId, unclaimedFees0, unclaimedFees1);
    }

    /**
     * @notice Calculate unclaimed fees for a position
     */
    function calculateUnclaimedFees(
        uint256 amount,
        uint256 entryFeeGrowth,
        uint256 currentFeeGrowth,
        uint256 feesClaimed
    ) internal pure returns (uint256) {
        return ((amount * (currentFeeGrowth - entryFeeGrowth)) / 1e18) - feesClaimed;
    }

    /**
     * @notice Close a position and withdraw liquidity
     * @param positionId The ID of the position to close
     */
    function closePosition(uint256 positionId) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender, positionId), "Not authorized");
        require(positions[positionId].amount0 > 0 || positions[positionId].amount1 > 0, "Position does not exist");
        Position storage position = positions[positionId];
        
        uint256 amount0 = position.amount0;
        uint256 amount1 = position.amount1;
        
        // Collect any remaining fees
        collectFees(positionId);
        
        // Update totals
        totalAmount0 -= amount0;
        totalAmount1 -= amount1;
        
        // Clear position
        delete positions[positionId];
        
        // Burn NFT
        _burn(positionId);
        
        // Transfer tokens
        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);
        
        emit PositionClosed(msg.sender, positionId, amount0, amount1);
    }

    /**
     * @notice Update the swap fee rate
     * @param newFeeRate New fee rate (base 10000)
     */
    function updateFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= 100, "Fee rate too high"); // Max 1%
        swapFeeRate = newFeeRate;
        emit FeeRateUpdated(newFeeRate);
    }

    /**
     * @notice Get position details
     * @param positionId The ID of the position
     */
    function getPosition(uint256 positionId) external view returns (
        uint256 amount0,
        uint256 amount1,
        uint256 feesClaimed0,
        uint256 feesClaimed1,
        uint256 unclaimedFees0,
        uint256 unclaimedFees1
    ) {
        Position storage position = positions[positionId];
        
        unclaimedFees0 = calculateUnclaimedFees(
            position.amount0,
            position.entryFeeGrowthGlobal0,
            feeGrowthGlobal0,
            position.feesClaimed0
        );
        
        unclaimedFees1 = calculateUnclaimedFees(
            position.amount1,
            position.entryFeeGrowthGlobal1,
            feeGrowthGlobal1,
            position.feesClaimed1
        );
        
        return (
            position.amount0,
            position.amount1,
            position.feesClaimed0,
            position.feesClaimed1,
            unclaimedFees0,
            unclaimedFees1
        );
    }

    function _isApprovedOrOwner(address user, uint256 positionId) internal view returns (bool) {
        return user == owner() || isApprovedForAll(owner(), user) || getApproved(positionId) == user;
    }
}