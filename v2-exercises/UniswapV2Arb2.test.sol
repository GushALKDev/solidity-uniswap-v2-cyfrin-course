// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "../../../src/interfaces/IERC20.sol";
import {IWETH} from "../../../src/interfaces/IWETH.sol";
import {IUniswapV2Router02} from
    "../../../src/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import {
    DAI,
    WETH,
    UNISWAP_V2_ROUTER_02,
    UNISWAP_V2_PAIR_DAI_WETH,
    SUSHISWAP_V2_ROUTER_02,
    SUSHISWAP_V2_PAIR_DAI_WETH
} from "../../../src/Constants.sol";
import {UniswapV2Arb2} from "./UniswapV2Arb2.sol";

// Test arbitrage between Uniswap and Sushiswap
// Buy WETH on Uniswap, sell on Sushiswap.
// For flashSwap, borrow DAI from DAI/MKR pair
contract UniswapV2Arb2Test is Test {
    IUniswapV2Router02 private constant uni_router =
        IUniswapV2Router02(UNISWAP_V2_ROUTER_02);
    IUniswapV2Router02 private constant sushi_router =
        IUniswapV2Router02(SUSHISWAP_V2_ROUTER_02);
    IERC20 private constant dai = IERC20(DAI);
    IWETH private constant weth = IWETH(WETH);
    address constant user = address(11);

    UniswapV2Arb2 private arb;

    function setUp() public {
        arb = new UniswapV2Arb2();

        // Setup - WETH cheaper on Uniswap than Sushiswap
        deal(address(this), 100 * 1e18);

        weth.deposit{value: 100 * 1e18}();
        weth.approve(address(uni_router), type(uint256).max);

        // Log prices BEFORE market manipulation
        _logPrices("BEFORE MANIPULATION");

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        uni_router.swapExactTokensForTokens({
            amountIn: 100 * 1e18,
            amountOutMin: 1,
            path: path,
            to: user,
            deadline: block.timestamp
        });

         // Log prices AFTER market manipulation
        _logPrices("AFTER MANIPULATION");

    }

    function test_flashSwap() public {
        uint256 bal0 = dai.balanceOf(user);
        vm.prank(user);
        arb.flashSwap(
            UNISWAP_V2_PAIR_DAI_WETH,
            SUSHISWAP_V2_PAIR_DAI_WETH,
            true,
            10000 * 1e18,
            1
        );
        uint256 bal1 = dai.balanceOf(user);

        assertGt(bal1, bal0, "no profit");
        assertEq(dai.balanceOf(address(arb)), 0, "DAI balance of arb != 0");
        console2.log("Profit:", (bal1 - bal0)/1e18);
    }

    function _logPrices(string memory stage) private view {
        // Get quote for 1 WETH in both DEXs (how much DAI we get for 1 WETH)
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        uint256[] memory uniAmounts = uni_router.getAmountsOut(1e18, path);
        uint256[] memory sushiAmounts = sushi_router.getAmountsOut(1e18, path);

        uint256 uniPrice = uniAmounts[1]; // DAI per WETH on Uniswap
        uint256 sushiPrice = sushiAmounts[1]; // DAI per WETH on Sushiswap

        console2.log(string(abi.encodePacked("=== PRICES ", stage, " ===")));
        console2.log("Uniswap WETH price (DAI):", uniPrice);
        console2.log("Sushiswap WETH price (DAI):", sushiPrice);
        
        // Calculate price difference in percentage first
        uint256 priceSpreadPercentage = 0;
        if (sushiPrice != uniPrice) {
            priceSpreadPercentage = sushiPrice > uniPrice 
                ? ((sushiPrice - uniPrice) * 100) / uniPrice
                : ((uniPrice - sushiPrice) * 100) / sushiPrice;
            console2.log("Price spread percentage:", priceSpreadPercentage);
        }
        
        // Only show arbitrage opportunity if spread > 1%
        if (priceSpreadPercentage > 1) {
            if (sushiPrice > uniPrice) {
                uint256 diffBps = ((sushiPrice - uniPrice) * 10000) / uniPrice;
                console2.log("Sushiswap is more expensive by (bps):", diffBps);
                console2.log("Arbitrage opportunity: Buy WETH on Uniswap, sell on Sushiswap");
            } else if (uniPrice > sushiPrice) {
                uint256 diffBps = ((uniPrice - sushiPrice) * 10000) / sushiPrice;
                console2.log("Uniswap is more expensive by (bps):", diffBps);
                console2.log("Arbitrage opportunity: Buy WETH on Sushiswap, sell on Uniswap");
            }
        } else {
            console2.log("Price difference <= 1% - No profitable arbitrage opportunity");
        }
        
        console2.log("==========================================");
    }
}
