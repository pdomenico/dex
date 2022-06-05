//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./MyToken.sol";
import "forge-std/Test.sol";

error NotEnoughLiquidity();
error TokenSpendingNotAllowed();

contract EasyDex {
    MyToken token;
    // 1 eth is worth 100 tokens
    uint constant PRICE = 0.01 ether;

    event TokensBought(address indexed from, uint amount);
    event TokensSold(address indexed from, uint amount);

    constructor(address tokenAddress) {
        token = MyToken(tokenAddress);
    }

    function buy() external payable {
        require(msg.value > 0);
        uint amount = (msg.value / PRICE) * 10e17;
        console.log("This is amount: ", amount);

        if (token.balanceOf(address(this)) < amount)
            revert NotEnoughLiquidity();

        bool sent = token.transfer(msg.sender, amount);
        require(sent);
        emit TokensBought(msg.sender, amount);
    }

    function sell(uint amount) external {
        if (token.allowance(msg.sender, address(this)) < amount)
            revert TokenSpendingNotAllowed();

        uint ethAmount = amount / PRICE;
        if (address(this).balance < ethAmount) revert NotEnoughLiquidity();

        bool received = token.transferFrom(msg.sender, address(this), amount);
        (bool sent, ) = msg.sender.call{value: ethAmount}("");
        require(received && sent);
        emit TokensSold(msg.sender, amount);
    }

    fallback() external payable {}

    receive() external payable {}
}
