// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryPlatform is Ownable {
    event TreasuryAdded(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event NativeReceived(
        address indexed sender,
        uint256 amount
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function addTreasury(
        address _tokenAddress,
        uint256 amount
    ) external payable {
        require(amount > 0, "Amount must be greater than 0");

        if (_tokenAddress == address(0)) {
            require(msg.value == amount, "Incorrect native amount");

            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            require(msg.value == 0, "Do not send native token");

            bool success = IERC20(_tokenAddress).transferFrom(
                msg.sender,
                owner(),
                amount
            );

            require(success, "Transfer failed");
        }

        emit TreasuryAdded(_tokenAddress, msg.sender, amount);
    }

    receive() external payable {
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit NativeReceived(msg.sender, msg.value);
    }
}
