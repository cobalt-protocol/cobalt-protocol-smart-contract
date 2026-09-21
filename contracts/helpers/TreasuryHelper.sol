// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library TreasuryHelper {
    event TreasuryAdded(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    function _addTreasuryFrom(
        address recipient,
        address sender,
        address _tokenAddress,
        uint256 amount
    ) internal {
        require(amount > 0, "Amount must be greater than 0");

        if (_tokenAddress == address(0)) {
            require(msg.value == amount, "Incorrect native amount");

            (bool success, ) = payable(recipient).call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            require(msg.value == 0, "Do not send native token");

            bool success = IERC20(_tokenAddress).transferFrom(
                sender,
                recipient,
                amount
            );

            require(success, "Transfer failed");
        }

        emit TreasuryAdded(_tokenAddress, sender, amount);
    }
}
