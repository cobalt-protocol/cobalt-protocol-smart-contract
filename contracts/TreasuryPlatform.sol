// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TreasuryHelper} from "./helpers/TreasuryHelper.sol";

contract TreasuryPlatform is Ownable {
    event NativeReceived(address indexed sender, uint256 amount);

    event OwnerUpdated(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function updateOwner(address newOwner) external onlyOwner {
        address previousOwner = owner();
        transferOwnership(newOwner);
        emit OwnerUpdated(previousOwner, newOwner);
    }

    function addTreasury(
        address _tokenAddress,
        uint256 amount
    ) external payable {
        TreasuryHelper._addTreasuryFrom(
            owner(),
            msg.sender,
            _tokenAddress,
            amount
        );
    }

    function addTreasuryFrom(
        address sender,
        address _tokenAddress,
        uint256 amount
    ) external payable {
        TreasuryHelper._addTreasuryFrom(owner(), sender, _tokenAddress, amount);
    }

    receive() external payable {
        (bool success, ) = payable(owner()).call{value: msg.value}("");
        require(success, "Transfer failed");

        emit NativeReceived(msg.sender, msg.value);
    }
}
