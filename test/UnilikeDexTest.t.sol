// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/UniLikeDex.sol";
import "../src/MyToken.sol";

contract UnilikeDexTest is Test {
    UniLikeDex dex;
    MyToken token;
    uint constant FEE = 2;

    event AddedLiquidity(
        address indexed from,
        uint ethAmount,
        uint tokenAmount,
        uint tokensMinted
    );
    event WithdrawnLiquidity(
        address indexed from,
        uint ethAmount,
        uint tokenAmount,
        uint tokensBurned
    );
    event SwappedEthForTokens(
        address indexed from,
        uint ethAmount,
        uint tokenAmount
    );
    event SwappedTokensForEth(
        address indexed from,
        uint ethAmount,
        uint tokenAmount
    );

    fallback() external payable {}

    receive() external payable {}

    function setUp() public {
        token = new MyToken();
        dex = new UniLikeDex(address(token));
    }

    // Add liquidity with proportion 1ETH = 10 tokens
    function addLiquidity() public {
        token.sendTokens(address(this), 2**20 * 1e18);
        token.approve(address(dex), 2**20 * 1e18);
        dex.addLiquidity{value: 20 ether}(200 ether);
    }

    function testLiquidity() public {
        vm.expectEmit(true, true, true, true);
        emit AddedLiquidity(address(this), 20 ether, 200 ether, 100 ether);
        addLiquidity();
        assertEq(address(dex).balance, 20 ether);
        assertEq(token.balanceOf(address(dex)), 200 ether);
        assertEq(dex.balanceOf(address(this)), 100 ether);
    }

    function testFailLiquidity0ETH() public {
        token.approve(address(dex), 10000 ether);
        dex.addLiquidity{value: 0}(200 ether);
    }

    function testFailLiquidity0TKN() public {
        token.approve(address(dex), 10000 ether);
        dex.addLiquidity{value: 20 ether}(0);
    }

    function testLiquidityNotEnoughToken() public {
        addLiquidity();
        vm.expectRevert(NotEnoughTokens.selector);
        dex.addLiquidity{value: 20 ether}(100 ether);
    }

    function testAdditionalLiquidity() public {
        addLiquidity();
        uint ethReserve = address(dex).balance;
        uint tokenAmount = 100 ether;
        uint ethAmount = 1 ether;
        uint lpAmountExpected = (ethAmount * dex.totalSupply()) / ethReserve;

        token.approve(address(dex), tokenAmount);
        vm.expectEmit(true, true, true, true);
        emit AddedLiquidity(
            address(this),
            ethAmount,
            ethAmount * 10,
            lpAmountExpected
        );
        dex.addLiquidity{value: ethAmount}(tokenAmount);

        assertEq(address(dex).balance, ethReserve + ethAmount);
        assertEq(token.balanceOf(address(dex)), (ethAmount * 10) + 200 ether);
        assertEq(dex.balanceOf(address(this)), 100 ether + lpAmountExpected);
    }

    function testPriceEthForToken() public {
        addLiquidity();
        uint ethReserve = address(dex).balance;
        uint tokenReserve = token.balanceOf(address(dex));
        uint ethAmount = 0.1 ether;
        uint tokenExpectedAmount = (ethAmount * tokenReserve * (1000 - FEE)) /
            ((1000 * ethReserve) + (ethAmount * (1000 - FEE)));

        uint tokenActualAmount = dex.getAmountOut(
            ethAmount,
            ethReserve,
            tokenReserve
        );
        assertEq(tokenExpectedAmount, tokenActualAmount);
    }

    function testPriceTokenForEth() public {
        addLiquidity();
        uint ethReserve = address(dex).balance;
        uint tokenReserve = token.balanceOf(address(dex));
        uint tokenAmount = 0.1 ether;
        uint ethExpectedAmount = (tokenAmount * ethReserve * (1000 - FEE)) /
            ((1000 * tokenReserve) + (tokenAmount * (1000 - FEE)));

        uint ethActualAmount = dex.getAmountOut(
            tokenAmount,
            tokenReserve,
            ethReserve
        );
        assertEq(ethExpectedAmount, ethActualAmount);
    }

    function swapEthForToken(uint ethAmount) public {
        addLiquidity();
        uint ethReserve = address(dex).balance;
        uint tokenReserve = token.balanceOf(address(dex));
        uint tokenOut = dex.getAmountOut(ethAmount, ethReserve, tokenReserve);

        uint tokenBalance = token.balanceOf(address(this));
        uint ethBalance = address(this).balance;
        vm.expectEmit(true, true, true, true);
        emit SwappedEthForTokens(address(this), ethAmount, tokenOut);
        vm.expectCall(
            address(token),
            abi.encodeCall(token.transfer, (address(this), tokenOut))
        );
        dex.swapEthForTokens{value: ethAmount}();

        assertEq(token.balanceOf(address(this)), tokenBalance + tokenOut);
        assertEq(address(this).balance, ethBalance - ethAmount);
    }

    function swapTokensForEth(uint tokenAmount) public {
        addLiquidity();
        uint ethReserve = address(dex).balance;
        uint tokenReserve = token.balanceOf(address(dex));
        uint ethExpectedReceived = dex.getAmountOut(
            tokenAmount,
            tokenReserve,
            ethReserve
        );

        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        vm.expectEmit(true, true, true, true);
        emit SwappedTokensForEth(
            address(this),
            ethExpectedReceived,
            tokenAmount
        );
        vm.expectCall(
            address(token),
            abi.encodeCall(
                token.transferFrom,
                (address(this), address(dex), tokenAmount)
            )
        );
        dex.swapTokensForEth(tokenAmount);

        assertEq(token.balanceOf(address(this)), tokenBalance - tokenAmount);
        assertEq(address(this).balance, ethBalance + ethExpectedReceived);
    }

    function testSwaps() public {
        token.sendTokens(address(this), (2**20) * 1e18);

        for (uint i = 1; i < 11; i++) {
            swapEthForToken(2**i * 1e18);
            swapTokensForEth(2**i * 1e18);
        }
    }

    function testRemoveAllLiquidity() public {
        // Do 1 eth to 10 tokens swap first
        swapEthForToken(1 ether);

        vm.expectEmit(true, true, true, true);
        emit WithdrawnLiquidity(
            address(this),
            address(dex).balance,
            token.balanceOf(address(dex)),
            100 ether
        );
        dex.removeLiquidity(100 ether);

        assertEq(dex.totalSupply(), 0 ether);
        assertEq(token.balanceOf(address(dex)), 0 ether);
        assertEq(dex.balanceOf(address(this)), 0 ether);
        assertEq(address(dex).balance, 0 ether);
    }

    function testRemoveHalfLiquidity() public {
        // Initial swap
        swapEthForToken(1 ether);

        uint ethReserve = address(dex).balance;
        uint tokenReserve = token.balanceOf(address(dex));
        uint ethWithdrawn = address(dex).balance / 2;
        uint tokenWithdrawn = token.balanceOf(address(dex)) / 2;
        uint lpTokensToBurn = dex.balanceOf(address(this)) / 2;

        vm.expectEmit(true, true, true, true);
        emit WithdrawnLiquidity(
            address(this),
            ethWithdrawn,
            tokenWithdrawn,
            lpTokensToBurn
        );
        dex.removeLiquidity(lpTokensToBurn);

        assertEq(dex.totalSupply(), 50 ether);
        assertEq(token.balanceOf(address(dex)), tokenReserve - tokenWithdrawn);
        assertEq(address(dex).balance, ethReserve - ethWithdrawn);
    }
}
