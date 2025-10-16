// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IUniswapV2Pair} from
    "../../../src/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import {IERC20} from "../../../src/interfaces/IERC20.sol";
import {console2} from "forge-std/console2.sol";

contract UniswapV2Arb2 {
    
    error InsufficientProfit();

    struct FlashSwapData {
        // Caller of flashSwap (msg.sender inside flashSwap)
        address caller;
        // Pair to flash swap from
        address pair0;
        // Pair to swap from
        address pair1;
        // True if flash swap is token0 in and token1 out
        bool isZeroForOne;
        // Amount in to repay flash swap
        uint256 amountIn;
        // Amount to borrow from flash swap
        uint256 amountOut;
        // Revert if profit is less than this minimum
        uint256 minProfit;
    }

    // Exercise 1
    // - Flash swap to borrow tokenOut
    /**
     * @param pair0 Pair contract to flash swap
     * @param pair1 Pair contract to swap
     * @param isZeroForOne True if flash swap is token0 in and token1 out
     * @param amountIn Amount in to repay flash swap
     * @param minProfit Minimum profit that this arbitrage must make
     */
    function flashSwap(
        address pair0,
        address pair1,
        bool isZeroForOne,
        uint256 amountIn,
        uint256 minProfit
    ) external {
        // Write your code here
        // Don’t change any other code

        // calculate amountOut
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair0).getReserves();

        uint256 reserveIn = isZeroForOne ? reserve0 : reserve1;
        uint256 reserveOut = isZeroForOne ? reserve1 : reserve0;

        uint256 amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        FlashSwapData memory data = FlashSwapData({
            caller: msg.sender,
            pair0: pair0,
            pair1: pair1,
            isZeroForOne: isZeroForOne, 
            amountIn: amountIn,
            amountOut: amountOut,
            minProfit: minProfit
        });

        // initiate flash swap, getting WETH (pair 2) with a value of 10000 DAI (amountIn)
        IUniswapV2Pair(pair0).swap({
            amount0Out: isZeroForOne ? 0 : amountOut,
            amount1Out: isZeroForOne ? amountOut: 0,
            to: address(this),
            data: abi.encode(data)
        });
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external {
        // Write your code here
        // Don’t change any other code
        
        // Decode data
        (FlashSwapData memory flashData) = abi.decode(data, (FlashSwapData));
        
        address token0 = IUniswapV2Pair(flashData.pair0).token0();
        address token1 = IUniswapV2Pair(flashData.pair0).token1();

        (address tokenIn, address tokenOut) = flashData.isZeroForOne ? (token0, token1) : (token1, token0);

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(flashData.pair1).getReserves();

        // calculate amountOut in DAI (pair 1)
        uint256 reserveIn = flashData.isZeroForOne ? reserve1 : reserve0;
        uint256 reserveOut = flashData.isZeroForOne ? reserve0 : reserve1;

        uint256 amountOut = getAmountOut(flashData.amountOut, reserveIn, reserveOut);

        // Send borrowed token WETH to pair1
        IERC20(tokenOut).transfer(flashData.pair1, flashData.amountOut);

        // Perform the arbitrage, getting DAI (pair 1) with a value of amountOut
        IUniswapV2Pair(flashData.pair1).swap({
            amount0Out: flashData.isZeroForOne ? amountOut : 0,
            amount1Out: flashData.isZeroForOne ? 0 : amountOut,
            to: address(this),
            data: ""
        });

        // check profit amountOut (DAI) - flashData.amountIn (DAI)
        uint256 profit = amountOut - flashData.amountIn;
        if (profit < flashData.minProfit) {
            revert InsufficientProfit();
        }
    
        // repay flash swap
        IERC20(tokenIn).transfer(flashData.pair0, flashData.amountIn);

        // send profit to caller
        IERC20(tokenIn).transfer(flashData.caller, profit); 
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
