pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                // NOTE: salt
                keccak256(abi.encodePacked(token0, token1)),
                // NOTE: keccak256(creation bytecode)
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        // NOTE: token 0 < token 1
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // NOTE:
        // dy = dx * y0 / x0
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // NOTE:
        // fee = 0.3%
        // 1 - fee = 0.997

        // x0 = reserveIn
        // y0 = reserveOut

        // dx = amountIn

        // NOTE: LOOKING FOR -> dy = amountOut

        //       dx * 0.997 * y0
        // dy = ------------------
        //       x0 + dx * 0.997

        //        amountIn * (997 / 1000) * reserveOut
        //    = ---------------------------------
        //       reserveIn + amountIn * (997 / 1000)

        //        amountIn * 997 * reserveOut
        //    = ---------------------------------
        //       reserveIn * 1000 + amountIn * 997

        // NOTE:
        // amountInWithFee = amountIn * 997
        uint amountInWithFee = amountIn.mul(997);
        
        // numerator = (amountIn * 997) * reserveOut
        uint numerator = amountInWithFee.mul(reserveOut);
        
        // denominator = reserveIn * 1000 + amountIn * 997
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);

        //         numerator
        // dy = ---------------
        //        denominator
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        // x0 * dy * 1000
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        // (y0 - dy) * 997 
        uint denominator = reserveOut.sub(amountOut).mul(997);
        // NOTE:
        // L**2 after the swap must be == than L**2 before the swap
        // (x0 + dx * (1 - f))(y0 - dy) == L**2 == x0 * y0

        //       x0 * dy       1
        // dx = --------- * -------
        //       y0 - dy     1 - f

        //       x0 * dy * 1000
        // dx = ----------------- 
        //      (y0 - dy) * 997
        
        // NOTE: round up
        // Add 1 to round up the result, ensuring we don't underestimate the required input amount
        // This prevents potential rounding down issues that could lead to insufficient input
        // Example: 1005 / 10 = 100.5 -> rounds down to 100, but we need 101 to cover the full amount
        amountIn = (numerator / denominator).add(1);
        }

    // performs chained getAmountOut calculations on any number of pairs
    // NOTE: amounts[0] = amountIn
    //       amounts[n - 1] = final amount out
    //       amounts[i] = intermediate amounts out
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;

        // NOTE: Example
        // --- Inputs ---
        // amountIn = 1e18
        // path = [WETH, DAI, MKR]
        // --- Outputs ---
        // WETH    1000000000000000000 (1 * 1e18)
        // DAI  4162271805086561934331 (4162.2718... * 1e18)
        // MKR       45574706621007603 (0.0455... * 1e18)

        // --- Execution ---
        // amounts = [0, 0, 0]
        // amounts = [1000000000000000000, 0, 0]

        // For loop
        // i = 0
        // path[i] = WETH, path[i + 1] = DAI
        // amounts[i] = 1000000000000000000
        // amounts[i + 1] = 4162271805086561934331
        // amounts = [1000000000000000000, 4162271805086561934331, 0]

        // i = 1
        // path[i] = DAI, path[i + 1] = MKR
        // amounts[i] = 4162271805086561934331
        // amounts[i + 1] = 45574706621007603
        // amounts = [1000000000000000000, 4162271805086561934331, 45574706621007603]

        // NOTE:
        //   i | path[i]   | path[i + 1]
        //   0 | path[0]   | path[1]
        //   1 | path[1]   | path[2]
        //   2 | path[2]   | path[3]
        // n-2 | path[n-2] | path[n-1]
        for (uint i; i < path.length - 1; i++) {
            // NOTE: reserves = internal balance of tokens inside the pair contract
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            // NOTE: use the previous output amount as the next input amount
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
            // path = [DAI, WETH]
            // amounts [0] = 1000 * 10 ** 18 DAI
            // amounts [1] = WETH amount out

            // path = [DAI, WETH, MKR]
            // amounts [0] = 1000 * 10 ** 18 DAI
            // amounts [1] = WETH amount out
            // amounts [2] = MKR amount
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;

        // --- Inputs ---
        // amountOut = 10000000000000000
        // path = [WETH, DAI, MKR]
        // --- Outputs ---
        // WETH       4569775674251490 (0.004569... * 1e18)
        // DAI   19031473161805224895 (19.031... * 1e18)
        // MKR   10000000000000000 (0.01 * 1e18)

        // --- Execution ---
        // amounts = [0, 0, 0]
        // amounts = [0, 0, 10000000000000000]

        // For loop
        // i = 2
        // path[i - 1] = DAI, path[i] = MKR
        // amounts[i] = 10000000000000000
        // amounts[i - 1] = 19031473161805224895
        // amounts = [0, 19031473161805224895, 10000000000000000]

        // i = 1
        // path[i - 1] = WETH, path[i] = DAI
        // amounts[i] = 19031473161805224895
        // amounts[i - 1] = 4569775674251490
        // amounts = [4569775674251490, 19031473161805224895, 10000000000000000]

        // NOTE:
        // i     | output amount  | input amount
        // n - 1 | amounts[n - 1] | amounts[n - 2]
        // n - 2 | amounts[n - 2] | amounts[n - 3]
        // ...
        // 2     | amounts[2]     | amounts[1] 
        // 1     | amounts[1]     | amounts[0]
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
