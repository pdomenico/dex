//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyToken is ERC20 {
    constructor() ERC20("MyToken", "MYTKN") {
        _mint(msg.sender, 1000e18);
    }

    function sendTokens(address to, uint amount) public {
        _mint(to, amount);
    }
}
