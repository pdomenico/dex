// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/EasyDex.sol";
import "../src/MyToken.sol";

contract SimpleDexTest is Test {
    EasyDex dex;
    MyToken token;

    event TokensBought(address indexed from, uint amount);
    event TokensSold(address indexed from, uint amount);

    function setUp() public {
        token = new MyToken();
        dex = new EasyDex(address(token));

        // Give the dex 10,000 tokens and 100 eth
        deal(address(dex), 100 ether);
        token.sendTokens(address(dex), 10000 ether);
    }

    function testBuyNotEnoughLiquidity() public {
        vm.expectRevert(NotEnoughLiquidity.selector);
        dex.buy{value: address(this).balance}();
    }

    function testBuy() public {
        uint ethAmount = 1 ether;
        uint tokenAmount = 100 ether;
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit TokensBought(address(this), tokenAmount);
        dex.buy{value: ethAmount}();
        assertEq(ethBalance - ethAmount, address(this).balance);
        assertEq(tokenBalance + tokenAmount, token.balanceOf(address(this)));
    }

    function testSell() public {
        uint ethBalance = address(this).balance;
        uint tokenBalance = token.balanceOf(address(this));
        uint tokenAmount = 100 ether;
        uint ethAmount = 1 ether;

        token.approve(address(dex), tokenAmount);
        vm.expectEmit(true, true, true, true);
        emit TokensSold(address(this), tokenAmount);
        dex.sell(tokenAmount);
        assertEq(address(this).balance, ethBalance + 1 ether);
        assertEq(token.balanceOf(address(this)), tokenBalance - 100 ether);
    }

    fallback() external payable {}
}
