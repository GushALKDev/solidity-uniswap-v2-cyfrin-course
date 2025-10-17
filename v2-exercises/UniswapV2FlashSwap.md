# Uniswap V2 Flash Swap: Implementation Guide

## Introduction

This contract implements a **Flash Swap** using Uniswap V2. A flash swap allows you to borrow tokens from a liquidity pool without providing collateral upfront, with the condition that you must repay the loan (plus fees) within the same transaction.

## What is a Flash Swap?

A flash swap is a mechanism that allows you to:
- Borrow tokens from a Uniswap V2 pool
- Use those tokens for arbitrary operations
- Repay the borrowed amount plus fees in the same transaction
- If repayment fails, the entire transaction reverts

In this implementation, we're borrowing one token and repaying the same token plus fees - this is the standard behavior for a flash swap when you don't provide the paired token immediately.

**Important Note**: Although we use `pair.swap()`, we're not exchanging DAI for WETH. We're borrowing DAI and returning it with a fee. This is a legitimate flash swap pattern.

## Use Cases for Flash Swaps

### 1. Arbitrage
```
Pool A: 1 ETH = 2000 DAI
Pool B: 1 ETH = 2100 DAI
```
- Borrow 2000 DAI via flash swap
- Buy 1 ETH in Pool A
- Sell 1 ETH in Pool B for 2100 DAI
- Return 2000 DAI + fee (~6 DAI)
- Keep profit (~94 DAI)

### 2. Liquidations
- Borrow tokens to liquidate leveraged positions
- Use liquidation rewards to repay the flash swap

### 3. Debt refinancing
- Change collateral of a position without initial capital
- Pay expensive debt with cheaper borrowed funds

## Contract Flow

```
┌─────────────────┐
│      User       │
└─────────┬───────┘
          │ 1. flashSwap(DAI, 1M)
          ▼
┌─────────────────┐
│  UniswapV2      │
│   FlashSwap     │
└─────────┬───────┘
          │ 2. pair.swap(1M_DAI, 0, this, data)
          ▼
┌─────────────────┐
│  UniswapV2Pair  │ ← Sends 1M DAI to contract
│   (DAI/WETH)    │
└─────────┬───────┘
          │ 3. uniswapV2Call()
          ▼
┌─────────────────┐
│  UniswapV2      │
│   FlashSwap     │ ← Returns 1M DAI + 3,010 DAI fee
└─────────────────┘
```

## Key Implementation Details

### 1. `flashSwap()` Function

```solidity
function flashSwap(address token, uint256 amount) external {
    // Determine amount0Out and amount1Out
    (uint256 amount0Out, uint256 amount1Out) = (token == token0) ? (amount, uint256(0)) : (uint256(0), amount);

    // Encode data for callback
    bytes memory data = abi.encode(token, msg.sender);

    // Call swap - triggers the flash swap
    pair.swap(amount0Out, amount1Out, address(this), data);
}
```

**Key points**:
- Only one of `amount0Out` or `amount1Out` is > 0 (the token we're borrowing)
- Non-empty `data` parameter triggers flash swap behavior
- `pair.swap()` sends tokens FIRST and validates later in the callback

### 2. `uniswapV2Call()` Callback

```solidity
function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
    // Security validations
    require(msg.sender == address(pair), "Invalid caller");
    require(sender == address(this), "Invalid sender");

    // Decode data and calculate repayment
    (address token, address caller) = abi.decode(data, (address, address));
    uint256 amount = amount0 > 0 ? amount0 : amount1;
    uint256 fee = (amount * 3) / 997 + 1;
    uint256 amountToRepay = amount + fee;

    // Get fee from user and repay
    IERC20(token).transferFrom(caller, address(this), fee);
    IERC20(token).transfer(address(pair), amountToRepay);
}
```
```

## Flash Swap Fee Calculation

The Uniswap V2 fee is **0.3%** (3/1000), calculated as:

```solidity
uint256 fee = (amount * 3) / 997 + 1;
```

### Why 997 instead of 1000?

Uniswap V2 uses the invariant `x * y = k` with fees included. The fee calculation ensures:
```
(reserve0_new * reserve1_new) ≥ (reserve0_old * reserve1_old)
```

**Example** (1,000,000 DAI borrowed):
```
fee = (1,000,000 * 3) / 997 + 1 = 3,010 DAI
amountToRepay = 1,000,000 + 3,010 = 1,003,010 DAI
```

## Repayment Options

### Pattern 1: Same Token Repayment (our implementation)
```solidity
pair.swap(1000e18, 0, address(this), data); // Borrow 1000 DAI
// In callback:  
IERC20(DAI).transfer(pair, 1000e18 + fee); // Return DAI + fee
```

### Pattern 2: Cross-Token Repayment (alternative)
```solidity
pair.swap(1000e18, 0, address(this), data); // Borrow 1000 DAI
// In callback:
IERC20(WETH).transfer(pair, equivalentWETH + fee); // Return equivalent WETH + fee
```

**Our implementation uses Pattern 1** - the most common and straightforward approach. Pattern 2 is possible but requires additional price calculations to maintain the invariant.

## Security Measures

1. **Caller Validation**: Only the Uniswap pair can call the callback
2. **Sender Validation**: Prevents attacks where malicious contracts initiate swaps
3. **Token Validation**: Ensures only tokens from the pair can be borrowed

## Example Test

```solidity
function test_flashSwap() public {
    uint256 dai0 = dai.balanceOf(UNISWAP_V2_PAIR_DAI_WETH);
    
    vm.prank(user);
    flashSwap.flashSwap(DAI, 1e6 * 1e18); // 1M DAI flash swap
    
    uint256 dai1 = dai.balanceOf(UNISWAP_V2_PAIR_DAI_WETH);
    
    assertGe(dai1, dai0, "DAI balance of pair should increase");
}
```

## Conclusion

This implementation demonstrates a standard **Uniswap V2 Flash Swap**:

✅ **Core Features**:
- Borrow tokens from a liquidity pool without upfront collateral
- Execute arbitrary logic with borrowed tokens  
- Repay with same token + fee within single transaction
- Atomic operation - fails completely if repayment insufficient

✅ **Key Benefits**:
- No initial capital required for arbitrage/liquidation strategies
- Flexible repayment options (same token or equivalent value in paired token)
- Built-in security through callback validation and invariant checks

This pattern is commonly used for arbitrage, liquidations, and other DeFi strategies requiring temporary access to large amounts of capital.