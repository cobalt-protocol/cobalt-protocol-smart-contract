// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PriceCompetitionManager is Ownable {
    struct PriceCompetitionFee {
        uint256 id;
        uint256 treasuryFee;
        address tokenAddress;
        string title;
        string description;
    }

    uint256 private priceCompetitionFeeId;

    mapping(uint256 => PriceCompetitionFee) public priceCompetitionFees;

    event PriceCompetitionFeeSet(
        uint256 indexed id,
        uint256 treasuryFee,
        address indexed tokenAddress,
        string title,
        string description
    );

    event PriceCompetitionFeeUpdated(
        uint256 indexed id,
        uint256 treasuryFee,
        address indexed tokenAddress,
        string title,
        string description
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setPriceCompetitionFee(
        uint256 _treasuryFee,
        address _tokenAddress,
        string calldata _title,
        string calldata _description
    ) external onlyOwner {
        priceCompetitionFeeId++;

        priceCompetitionFees[priceCompetitionFeeId] = PriceCompetitionFee({
            id: priceCompetitionFeeId,
            treasuryFee: _treasuryFee,
            tokenAddress: _tokenAddress,
            title: _title,
            description: _description
        });

        emit PriceCompetitionFeeSet(
            priceCompetitionFeeId,
            _treasuryFee,
            _tokenAddress,
            _title,
            _description
        );
    }

    function updatePriceCompetitionFee(
        uint256 _priceCompetitionFeeId,
        uint256 _treasuryFee,
        address _tokenAddress,
        string calldata _title,
        string calldata _description
    ) external onlyOwner {
        require(
            priceCompetitionFees[_priceCompetitionFeeId].id != 0,
            "Price competition fee not found"
        );

        priceCompetitionFees[_priceCompetitionFeeId].treasuryFee = _treasuryFee;

        priceCompetitionFees[_priceCompetitionFeeId]
            .tokenAddress = _tokenAddress;

        priceCompetitionFees[_priceCompetitionFeeId].title = _title;

        priceCompetitionFees[_priceCompetitionFeeId].description = _description;

        emit PriceCompetitionFeeUpdated(
            _priceCompetitionFeeId,
            _treasuryFee,
            _tokenAddress,
            _title,
            _description
        );
    }

    function getPriceCompetitionFee(
        uint256 _priceCompetitionFeeId
    ) external view returns (PriceCompetitionFee memory) {
        return priceCompetitionFees[_priceCompetitionFeeId];
    }
}

