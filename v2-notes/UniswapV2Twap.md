# TWAP (Time-Weighted Average Price) in Uniswap V2

## Table of Contents
1. [Introduction](#introduction)
2. [Theoretical Foundations](#theoretical-foundations)
3. [The Spot Price Problem](#the-spot-price-problem)
4. [How TWAP Works in Uniswap V2](#how-twap-works-in-uniswap-v2)
5. [Technical Implementation](#technical-implementation)
6. [TWAP Mathematics](#twap-mathematics)
7. [Data Structures](#data-structures)
8. [Operational Flow](#operational-flow)
9. [Use Cases](#use-cases)
10. [Limitations and Considerations](#limitations-and-considerations)
11. [Practical Examples](#practical-examples)
12. [Comparison with Uniswap V3](#comparison-with-uniswap-v3)

## Introduction

The **Time-Weighted Average Price (TWAP)** is a decentralized oracle mechanism implemented in Uniswap V2 that enables obtaining time-averaged prices that are resistant to manipulation and more stable than instantaneous spot prices.

### Why is TWAP Important?

- **Manipulation resistance**: Spot prices can be easily manipulated in a single transaction
- **Stability**: Provides more stable prices for DeFi applications
- **Decentralization**: Does not depend on external oracles
- **Gas efficiency**: Uses data already available in the protocol

## Theoretical Foundations

### What is a Time-Weighted Average Price?

TWAP is a method for calculating the average price of an asset over a specific time period, where each price is weighted by the duration of time it was active.

**Basic formula:**
```
TWAP = Σ(Price × Time) / Total_Time
```

### Cumulative Price Concept

Instead of storing all historical prices, Uniswap V2 uses **cumulative prices**:

```
cumulative_price(t) = Σ(price(i) × duration(i)) for all i from 0 to t
```

## The Spot Price Problem

### Instant Price Vulnerabilities

1. **Flash Loan Manipulation**: An attacker can manipulate the price in a single transaction
2. **Extreme volatility**: Prices can fluctuate dramatically between blocks
3. **MEV (Maximal Extractable Value)**: Prices can be manipulated by bots

### Manipulation Example

```solidity
// ❌ Vulnerable to manipulation
function vulnerablePrice() external view returns (uint256) {
    (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
    return reserve1 * 1e18 / reserve0; // Manipulable spot price
}
```

## How TWAP Works in Uniswap V2

### System Architecture

Uniswap V2 implements TWAP through:

1. **Automatic cumulative prices**: Each pair automatically updates cumulative prices
2. **External oracle contracts**: Contracts that read and process this data
3. **Observation periods**: Minimum intervals to prevent manipulation

### Data Flow

```mermaid
graph TD
    A[Swap in Pair] --> B[_update() called]
    B --> C[Calculate current spot price]
    C --> D[Update cumulative price]
    D --> E[Oracle reads data]
    E --> F[Calculate TWAP]
```

## Technical Implementation

### In the Pair Contract (UniswapV2Pair.sol)

```solidity
// State variables for TWAP
uint256 public price0CumulativeLast;
uint256 public price1CumulativeLast;
uint32 private blockTimestampLast;

function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
    require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
    uint32 blockTimestamp = uint32(block.timestamp % 2**32);
    uint32 timeElapsed = blockTimestamp - blockTimestampLast;
    
    if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
        // Update cumulative prices
        price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
        price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
    }
    
    reserve0 = uint112(balance0);
    reserve1 = uint112(balance1);
    blockTimestampLast = blockTimestamp;
}
```

### In the Oracle Contract

```solidity
contract UniswapV2Twap {
    using FixedPoint for *;

    uint256 private constant MIN_WAIT = 300; // 5 minutes minimum
    
    IUniswapV2Pair public immutable pair;
    address public immutable token0;
    address public immutable token1;

    // Last observed cumulative prices
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public updatedAt;

    // Calculated TWAPs
    FixedPoint.uq112x112 public price0Avg;
    FixedPoint.uq112x112 public price1Avg;
```

## TWAP Mathematics

### Cumulative Price Calculation

For each update:

```
new_cumulative_price = previous_cumulative_price + (spot_price × elapsed_time)
```

Where:
- `spot_price = reserve1/reserve0` (for token0 in terms of token1)
- `elapsed_time = current_timestamp - previous_timestamp`

### TWAP Calculation

```
TWAP = (cumulative_price_end - cumulative_price_start) / (time_end - time_start)
```

### Numerical Example

```python
# Example data
timestamps = [1, 3, 4, 7, 11]  # seconds
prices = [1000, 1100, 1300, 1200]  # USDC per ETH

# Calculate cumulative prices
cumulative_prices = [0]
cumulative_price = 0

for i in range(len(timestamps) - 1):
    dt = timestamps[i + 1] - timestamps[i]
    price = prices[i]
    cumulative_price += dt * price
    cumulative_prices.append(cumulative_price)

# cumulative_prices = [0, 2000, 3100, 7000, 11800]

# TWAP from start to end
dt_total = timestamps[-1] - timestamps[0]  # 11 - 1 = 10
twap = (cumulative_prices[-1] - cumulative_prices[0]) / dt_total
# twap = (11800 - 0) / 10 = 1180 USDC per ETH
```

## Data Structures

### UQ112x112 Type

Uniswap V2 uses the UQ112x112 fixed-point format:

```solidity
struct uq112x112 {
    uint224 _x;
}
```

- **Range**: [0, 2^112 - 1]
- **Resolution**: 1 / 2^112
- **112 bits**: integer part
- **112 bits**: fractional part

### Fixed-Point Format Advantages

1. **Precision**: Maintains decimal precision without using floating-point
2. **Efficiency**: More efficient operations than decimal arithmetic
3. **Controlled overflow**: Designed to handle overflow safely

## Operational Flow

### 1. Oracle Initialization

```solidity
constructor(address _pair) {
    pair = IUniswapV2Pair(_pair);
    token0 = pair.token0();
    token1 = pair.token1();
    
    // Store initial state
    price0CumulativeLast = pair.price0CumulativeLast();
    price1CumulativeLast = pair.price1CumulativeLast();
    (,, updatedAt) = pair.getReserves();
}
```

### 2. Oracle Update

```solidity
function update() external {
    uint32 blockTimestamp = uint32(block.timestamp);
    uint32 dt = blockTimestamp - updatedAt;
    
    require(dt >= MIN_WAIT, "Insufficient time elapsed");
    
    // Get current cumulative prices
    (uint256 price0Cumulative, uint256 price1Cumulative) = 
        _getCurrentCumulativePrices();
    
    // Calculate TWAP
    unchecked {
        price0Avg = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / dt)
        );
        price1Avg = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / dt)
        );
    }
    
    // Update state
    price0CumulativeLast = price0Cumulative;
    price1CumulativeLast = price1Cumulative;
    updatedAt = blockTimestamp;
}
```

### 3. Price Consultation

```solidity
function consult(address tokenIn, uint256 amountIn) 
    external view returns (uint256 amountOut) {
    
    require(tokenIn == token0 || tokenIn == token1, "Invalid token");
    
    if (tokenIn == token0) {
        // Price of token0 in terms of token1
        amountOut = FixedPoint.mul(price0Avg, amountIn).decode144();
    } else {
        // Price of token1 in terms of token0
        amountOut = FixedPoint.mul(price1Avg, amountIn).decode144();
    }
}
```

## Use Cases

### 1. Lending and Liquidations

```solidity
contract LendingProtocol {
    UniswapV2Twap oracle;
    
    function getLiquidationPrice(address asset) external view returns (uint256) {
        return oracle.consult(asset, 1e18) * LIQUIDATION_RATIO / 100;
    }
}
```

### 2. Algorithmic Stablecoins

```solidity
contract AlgorithmicStablecoin {
    UniswapV2Twap oracle;
    
    function rebase() external {
        uint256 twapPrice = oracle.consult(address(this), 1e18);
        
        if (twapPrice > TARGET_PRICE * 105 / 100) {
            // Expand supply
            _expandSupply();
        } else if (twapPrice < TARGET_PRICE * 95 / 100) {
            // Contract supply
            _contractSupply();
        }
    }
}
```

### 3. Derivatives and Options

```solidity
contract OptionsProtocol {
    UniswapV2Twap oracle;
    
    function exerciseOption(uint256 optionId) external {
        uint256 twapPrice = oracle.consult(underlyingAsset, 1e18);
        require(twapPrice >= strikePrice, "Option out of the money");
        
        _executeOption(optionId, twapPrice);
    }
}
```

## Limitations and Considerations

### 1. Price Latency

- **Problem**: TWAP is always delayed compared to current price
- **Impact**: May not reflect sudden market changes
- **Mitigation**: Use appropriate observation periods

### 2. Minimum Required Period

```solidity
uint256 private constant MIN_WAIT = 300; // 5 minutes
```

- **Reason**: Prevent manipulation in short periods
- **Trade-off**: Lower responsiveness vs higher security

### 3. Sandwich Attacks

While TWAP is resistant to direct manipulation, it can be susceptible to:

- **Extended sandwich attacks**
- **Multi-block manipulation**
- **Coordinated attacks**

### 4. Low Liquidity

In pools with low liquidity:

- **Higher price volatility**
- **Greater impact from individual trades**
- **Less reliable TWAP**

## Practical Examples

### Example 1: Manual TWAP Calculation

```python
def calculate_twap(price_observations, timestamps):
    """
    Calculate TWAP given price observations and timestamps
    """
    if len(price_observations) != len(timestamps) - 1:
        raise ValueError("Incorrect dimensions")
    
    cumulative_price = 0
    cumulative_time = 0
    
    for i in range(len(price_observations)):
        dt = timestamps[i + 1] - timestamps[i]
        cumulative_price += price_observations[i] * dt
        cumulative_time += dt
    
    return cumulative_price / cumulative_time

# Usage example
timestamps = [0, 100, 200, 300, 400]  # seconds
prices = [1000, 1050, 950, 1100]      # USDC per ETH

twap = calculate_twap(prices, timestamps)
print(f"TWAP: {twap} USDC per ETH")  # TWAP: 1025.0 USDC per ETH
```

### Example 2: Simplified Implementation

```solidity
contract SimpleTWAP {
    struct Observation {
        uint256 priceCumulative;
        uint32 timestamp;
    }
    
    mapping(address => Observation[]) public observations;
    uint256 public constant PERIOD = 1 hours;
    
    function update(address pair) external {
        IUniswapV2Pair(pair).sync(); // Force update
        
        uint256 priceCumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        uint32 timestamp = uint32(block.timestamp);
        
        observations[pair].push(Observation({
            priceCumulative: priceCumulative,
            timestamp: timestamp
        }));
    }
    
    function getTWAP(address pair) external view returns (uint256) {
        Observation[] memory obs = observations[pair];
        require(obs.length >= 2, "Insufficient observations");
        
        uint256 length = obs.length;
        Observation memory latest = obs[length - 1];
        Observation memory previous = obs[length - 2];
        
        uint32 dt = latest.timestamp - previous.timestamp;
        require(dt >= PERIOD, "Insufficient period");
        
        return (latest.priceCumulative - previous.priceCumulative) / dt;
    }
}
```

### Example 3: Manipulation Resistance Test

```solidity
contract TWAPTest is Test {
    UniswapV2Twap twap;
    IUniswapV2Pair pair;
    
    function test_manipulation_resistance() public {
        // Initial state
        twap.update();
        uint256 twapBefore = twap.consult(WETH, 1e18);
        
        // Manipulation attempt with large swap
        _performLargeSwap(1000 ether);
        
        // Spot price changes dramatically
        uint256 spotPrice = _getSpotPrice();
        assertGt(spotPrice, twapBefore * 2); // Spot price 2x higher
        
        // But TWAP remains stable
        skip(MIN_WAIT + 1);
        twap.update();
        uint256 twapAfter = twap.consult(WETH, 1e18);
        
        // TWAP changed less than 10%
        assertLt(twapAfter, twapBefore * 110 / 100);
        assertGt(twapAfter, twapBefore * 90 / 100);
    }
}
```

## Best Practices

### 1. Period Selection

```solidity
// ✅ Good practice: Appropriate period for use case
uint256 constant LENDING_PERIOD = 30 minutes;    // Lending
uint256 constant LIQUIDATION_PERIOD = 10 minutes; // Liquidations
uint256 constant GOVERNANCE_PERIOD = 24 hours;    // Governance decisions
```

### 2. Multiple Sources

```solidity
contract CompositeOracle {
    UniswapV2Twap twapOracle;
    ChainlinkOracle chainlinkOracle;
    
    function getPrice() external view returns (uint256) {
        uint256 twapPrice = twapOracle.consult(token, 1e18);
        uint256 chainlinkPrice = chainlinkOracle.latestAnswer();
        
        // Verify prices don't differ more than 5%
        require(
            abs(twapPrice - chainlinkPrice) < twapPrice * 5 / 100,
            "Price divergence"
        );
        
        return (twapPrice + chainlinkPrice) / 2;
    }
}
```

### 3. Emergency Handling

```solidity
contract SafeTWAP {
    bool public emergencyMode;
    uint256 public lastValidPrice;
    
    function getPrice() external view returns (uint256) {
        if (emergencyMode) {
            return lastValidPrice;
        }
        
        uint256 twapPrice = twap.consult(token, 1e18);
        
        // Verify sanity bounds
        require(
            twapPrice > MIN_REASONABLE_PRICE && 
            twapPrice < MAX_REASONABLE_PRICE,
            "Price out of range"
        );
        
        return twapPrice;
    }
    
    function activateEmergencyMode() external onlyOwner {
        emergencyMode = true;
        lastValidPrice = twap.consult(token, 1e18);
    }
}
```

## Advanced Considerations

### 1. Cumulative Price Overflow

Uniswap V2 is designed to handle overflow gracefully:

```solidity
// Overflow is desired and handled correctly
unchecked {
    price0CumulativeLast += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
}
```

The system works correctly as long as observations are made within 2^32 seconds (~136 years).

### 2. Gas Optimization

```solidity
contract GasOptimizedTWAP {
    // Pack multiple values into single storage slot
    struct PackedObservation {
        uint32 timestamp;
        uint224 priceCumulative;
    }
    
    PackedObservation public lastObservation;
    
    function update() external {
        (uint256 priceCumulative,, uint32 timestamp) = 
            UniswapV2OracleLibrary.currentCumulativePrices(pair);
            
        lastObservation = PackedObservation({
            timestamp: timestamp,
            priceCumulative: uint224(priceCumulative)
        });
    }
}
```

### 3. Multi-Hop TWAP

```solidity
contract MultiHopTWAP {
    UniswapV2Twap[] public oracles;
    address[] public tokens;
    
    function getMultiHopTWAP(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn
    ) external view returns (uint256) {
        uint256 currentAmount = amountIn;
        
        for (uint256 i = 0; i < oracles.length; i++) {
            currentAmount = oracles[i].consult(
                i == 0 ? tokenIn : tokens[i-1], 
                currentAmount
            );
        }
        
        return currentAmount;
    }
}
```

## Security Considerations

### 1. Oracle Manipulation Vectors

Even with TWAP, certain attacks are possible:

```solidity
// Example of potential manipulation over multiple blocks
contract MultiBlockManipulation {
    function executeAttack() external {
        // Block 1: Large buy to increase price
        _performLargeBuy();
        
        // Wait for next block...
        // Block 2: Maintain high price
        _maintainPrice();
        
        // Continue for minimum observation period...
        // This could influence TWAP if done consistently
    }
}
```

### 2. Mitigation Strategies

```solidity
contract SecureTWAPUsage {
    uint256 constant MAX_PRICE_CHANGE = 10; // 10% max change
    uint256 public lastTWAPPrice;
    
    function useTWAPPrice() external {
        uint256 currentTWAP = twap.consult(token, 1e18);
        
        if (lastTWAPPrice > 0) {
            uint256 priceChange = abs(currentTWAP - lastTWAPPrice) * 100 / lastTWAPPrice;
            require(priceChange <= MAX_PRICE_CHANGE, "Price change too large");
        }
        
        lastTWAPPrice = currentTWAP;
        
        // Use currentTWAP safely...
    }
}
```

## Testing Framework

### 1. TWAP Test Suite

```solidity
contract ComprehensiveTWAPTests is Test {
    UniswapV2Twap twap;
    IUniswapV2Pair pair;
    IERC20 token0;
    IERC20 token1;
    
    function setUp() public {
        // Deploy and initialize TWAP oracle
        pair = IUniswapV2Pair(UNISWAP_V2_PAIR_DAI_WETH);
        twap = new UniswapV2Twap(address(pair));
        
        token0 = IERC20(pair.token0());
        token1 = IERC20(pair.token1());
    }
    
    function test_basic_twap_calculation() public {
        // Test basic TWAP functionality
        skip(MIN_WAIT + 1);
        twap.update();
        
        uint256 twapPrice = twap.consult(address(token0), 1e18);
        assertGt(twapPrice, 0);
    }
    
    function test_manipulation_resistance() public {
        // Test resistance to manipulation
        twap.update();
        uint256 twapBefore = twap.consult(address(token0), 1e18);
        
        // Perform manipulation
        _manipulatePrice();
        
        skip(MIN_WAIT + 1);
        twap.update();
        uint256 twapAfter = twap.consult(address(token0), 1e18);
        
        // TWAP should not change dramatically
        assertApproxEqRel(twapAfter, twapBefore, 0.1e18); // Within 10%
    }
    
    function test_time_requirements() public {
        twap.update();
        
        // Should revert if called too soon
        vm.expectRevert(InsufficientTimeElapsed.selector);
        twap.update();
        
        // Should work after minimum time
        skip(MIN_WAIT + 1);
        twap.update(); // Should not revert
    }
}
```

## Conclusion

Uniswap V2's TWAP represents an elegant and efficient solution to the price oracle problem in DeFi. Its implementation based on cumulative prices provides:

- **Manipulation resistance** through time averaging
- **Gas efficiency** using already available data
- **Decentralization** without external dependencies
- **Simplicity** in design and implementation

While it has limitations such as price latency and the need for minimum periods, it remains a fundamental tool in the DeFi ecosystem for applications requiring stable and reliable prices.

The system's clever use of cumulative prices and fixed-point arithmetic demonstrates how mathematical elegance can solve complex real-world problems in decentralized finance. Understanding TWAP is crucial for developers building secure DeFi applications that depend on price feeds.

### Additional Resources

- [Official Uniswap V2 Documentation](https://docs.uniswap.org/contracts/v2/concepts/core-concepts/oracles)
- [Oracle Source Code](https://github.com/Uniswap/v2-periphery/tree/master/contracts/examples)
- [Uniswap V2 Whitepaper](https://uniswap.org/whitepaper.pdf)
- [TWAP Security Analysis](https://samczsun.com/so-you-want-to-use-a-price-oracle/)
- [Fixed-Point Arithmetic in Solidity](https://docs.uniswap.org/contracts/v2/guides/smart-contract-integration/building-an-oracle)

---

*This document provides a comprehensive view of Uniswap V2's TWAP system, from theoretical foundations to practical implementation. For production applications, always consult official documentation and consider security audits.*