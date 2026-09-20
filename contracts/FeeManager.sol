// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FeeManager is Ownable {
    struct PlatformFee {
        uint256 id;
        uint256 treasuryFee;
        string title;
        string description;
    }

    uint256 private platformFeeId;

    mapping(uint256 => PlatformFee) public feeManager;

    event FeesSet(
        uint256 indexed id,
        uint256 treasuryFee,
        string title,
        string description
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setFees(
        uint256 _treasuryFee,
        string memory _title,
        string memory _description
    ) external onlyOwner {
        platformFeeId++;

        feeManager[platformFeeId] = PlatformFee({
            id: platformFeeId,
            treasuryFee: _treasuryFee,
            title: _title,
            description: _description
        });

        emit FeesSet(platformFeeId, _treasuryFee, _title, _description);
    }

    function getFees(
        uint256 _platformFeeId
    ) external view returns (PlatformFee memory) {
        return feeManager[_platformFeeId];
    }
}

