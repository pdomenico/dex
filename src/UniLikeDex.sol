//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./MyToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

error SpendingNotAllowed();
error TxFailed();
error NotEnoughTokens();
error NoLiquidity();

contract UniLikeDex is ERC20 {
    MyToken token;
    uint public constant FEE = 2; // Fee is expressed in 1/1000, so 2 is 0,2%

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

    modifier onlyWithLiquidity() {
        if (address(this).balance == 0) revert NoLiquidity();
        _;
    }

    constructor(address tokenAddress) ERC20("MyTokenLP", "MYLP") {
        token = MyToken(tokenAddress);
    }

    function addLiquidity(uint maxTokenAmount) external payable {
        require(msg.value > 0 && maxTokenAmount > 0, "Value can't be 0!");
        if (token.allowance(msg.sender, address(this)) < maxTokenAmount)
            revert SpendingNotAllowed();

        uint ethReserve = address(this).balance - msg.value;

        // If it's initial liquidity, mint 100 LP tokens by default
        if (ethReserve == 0) {
            bool received = token.transferFrom(
                msg.sender,
                address(this),
                maxTokenAmount
            );
            _mint(msg.sender, 100e18);
            if (!received) revert TxFailed();
            emit AddedLiquidity(msg.sender, msg.value, maxTokenAmount, 100e18);
            return;
        }

        // Base case, new liquidity is added on top of already existing
        uint tokenAmount = ((msg.value * token.balanceOf(address(this))) /
            ethReserve);
        if (tokenAmount > maxTokenAmount) revert NotEnoughTokens();
        uint lpAmount = (msg.value * totalSupply()) / ethReserve;
        bool received = token.transferFrom(
            msg.sender,
            address(this),
            tokenAmount
        );
        _mint(msg.sender, lpAmount);

        if (!received) revert TxFailed();
        emit AddedLiquidity(msg.sender, msg.value, tokenAmount, lpAmount);
    }

    function removeLiquidity(uint lpTokensAmount) external onlyWithLiquidity {
        uint lpSupply = totalSupply();

        uint ethAmount = (lpTokensAmount * address(this).balance) / lpSupply;
        uint tokenAmount = (lpTokensAmount * token.balanceOf(address(this))) /
            lpSupply;

        _burn(msg.sender, lpTokensAmount);
        (bool ethSent, ) = msg.sender.call{value: ethAmount}("");
        bool tokensSent = token.transfer(msg.sender, tokenAmount);

        if (!(ethSent && tokensSent)) revert TxFailed();
        emit WithdrawnLiquidity(
            msg.sender,
            ethAmount,
            tokenAmount,
            lpTokensAmount
        );
    }

    // Calculates the amount of eth of tokens to give out in a swap, considering the fee
    function getAmountOut(
        uint tokenA,
        uint tokenAReserve,
        uint tokenBReserve
    ) public pure returns (uint) {
        uint numerator = tokenA * tokenBReserve * (1000 - FEE);
        uint denominator = (tokenAReserve * 1000) + (tokenA * (1000 - FEE));
        return numerator / denominator;
    }

    function swapEthForTokens() external payable onlyWithLiquidity {
        uint tokenAmount = getAmountOut(
            msg.value,
            address(this).balance - msg.value,
            token.balanceOf(address(this))
        );

        bool sent = token.transfer(msg.sender, tokenAmount);
        if (!sent) revert TxFailed();
        emit SwappedEthForTokens(msg.sender, msg.value, tokenAmount);
    }

    function swapTokensForEth(uint tokenAmount) external onlyWithLiquidity {
        if (token.allowance(msg.sender, address(this)) < tokenAmount)
            revert SpendingNotAllowed();

        uint ethAmount = getAmountOut(
            tokenAmount,
            token.balanceOf(address(this)),
            address(this).balance
        );
        bool received = token.transferFrom(
            msg.sender,
            address(this),
            tokenAmount
        );
        (bool sent, ) = msg.sender.call{value: ethAmount}("");
        if (!(sent && received)) revert TxFailed();
        emit SwappedTokensForEth(msg.sender, ethAmount, tokenAmount);
    }
}
