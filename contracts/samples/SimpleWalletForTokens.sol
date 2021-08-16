// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "./SimpleWallet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//in order to be created with tokens, the wallet has to have allowance to the paymaster in advance.
// the simplest strategy is assign the allowance in the constructor or init function
contract SimpleWalletForTokens is SimpleWallet {

    function init(address _singleton, address _owner, IERC20 token, address paymaster) external virtual {
        super.init(_singleton, _owner);
        token.approve(paymaster, type(uint).max);
    }
}
