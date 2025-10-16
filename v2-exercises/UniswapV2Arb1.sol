// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IUniswapV2Pair} from
    "../../../src/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from
    "../../../src/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import {IERC20} from "../../../src/interfaces/IERC20.sol";
import {console2} from "forge-std/console2.sol";

contract UniswapV2Arb1 {
    struct SwapParams {
        // Router to execute first swap - tokenIn for tokenOut
        address router0;
        // Router to execute second swap - tokenOut for tokenIn
        address router1;
        // Token in of first swap
        address tokenIn;
        // Token out of first swap
        address tokenOut;
        // Amount in for the first swap
        uint256 amountIn;
        // Revert the arbitrage if profit is less than this minimum
        uint256 minProfit;
    }

    function _swap(SwapParams memory params) internal returns (uint256 amountOut) {
        // Path decalaration
        address[] memory _getPath = new address[](2);

        // Approve & path for first swap
        IERC20(params.tokenIn).approve(params.router0,params.amountIn);
        _getPath[0] = params.tokenIn;
        _getPath[1] = params.tokenOut;

        // Execute first swap: tokenIn -> tokenOut
        uint256[] memory amountsSwap1 = IUniswapV2Router02(params.router0).swapExactTokensForTokens(
            params.amountIn,
            1,
            _getPath,
            address(this),
            block.timestamp
        );

        // Approve and path for second swap
        IERC20(params.tokenOut).approve(params.router1,amountsSwap1[1]);
        _getPath[0] = params.tokenOut;
        _getPath[1] = params.tokenIn; 

        // Execute second swap: tokenOut -> tokenIn
        uint256[] memory amountsSwap2 = IUniswapV2Router02(params.router1).swapExactTokensForTokens(
            amountsSwap1[1],
            1,
            _getPath,
            address(this),
            block.timestamp
        );

        return amountsSwap2[1];
    }

    // Exercise 1
    // - Execute an arbitrage between router0 and router1
    // - Pull tokenIn from msg.sender
    // - Send amountIn + profit back to msg.sender
    function swap(SwapParams calldata params) external {
        // Write your code here
        // Don’t change any other code

        // Pull tokenIn from msg.sender
        IERC20(params.tokenIn).transferFrom(msg.sender,address(this),params.amountIn);

        // Execute arbitrage
        uint256 profit = _swap(params);

        // Check if profit is sufficient
        require(profit >= params.minProfit, "Insufficient profit");

        // Send profit back to msg.sender
        IERC20(params.tokenIn).transfer(msg.sender, profit);
    }

    // Exercise 2
    // - Execute an arbitrage between router0 and router1 using flash swap
    // - Borrow tokenIn with flash swap from pair
    // - Send profit back to msg.sender
    /**
     * @param pair Address of pair contract to flash swap and borrow tokenIn
     * @param isToken0 True if token to borrow is token0 of pair
     * @param params Swap parameters
     */
    function flashSwap(address pair, bool isToken0, SwapParams calldata params)
        external
    {
        // Write your code here
        // Don’t change any other code

        // swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) 

        IUniswapV2Pair(pair).swap({
            amount0Out: isToken0 ? params.amountIn : 0,
            amount1Out: isToken0 ? 0 : params.amountIn,
            to: address(this),
            data: abi.encode(msg.sender, pair, params)
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
        (address caller, address pair, SwapParams memory params) = abi.decode(data, (address, address, SwapParams));
        
        // Security checks
        require(sender != address(0) && sender == address(this), "Invalid sender");
        require(pair == msg.sender, "Invalid pair");

        // Perform the arbitrage
        uint256 amountOut = _swap(params);

        // Calculate amount to repay
        uint256 fee = (params.amountIn * 3) / 997 + 1; // Uniswap fee calculation
        uint256 amountToRepay = params.amountIn + fee;

        // Ensure we have enough to repay
        uint256 profit = amountOut - amountToRepay;

        // Check if profit is sufficient
        require(profit >= params.minProfit, "Insufficient profit after flash swap");

        // Repay the flash swap
        IERC20(params.tokenIn).transfer(pair, amountToRepay);
        // Send profit to caller
        IERC20(params.tokenIn).transfer(caller, profit);
    }
}
