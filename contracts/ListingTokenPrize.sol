// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ListingTokenPrizeContract is Ownable {
    struct ListingTokenPrize {
        uint256 listingTokenPrizeId;
        address tokenAddress;
        bool isActive;
    }

    uint256 private listingTokenPrizeId;

    mapping(address => ListingTokenPrize) public listingToken;

    event ListingTokenPrizeAdded(
        uint256 indexed listingTokenPrizeId,
        address indexed tokenAddress,
        bool isActive
    );

    event ListingTokenPrizeDeactivated(
        uint256 indexed listingTokenPrizeId,
        address indexed tokenAddress,
        bool isActive
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function addListingTokenPrize(address _tokenAddress) external onlyOwner {
        require(
            listingToken[_tokenAddress].listingTokenPrizeId == 0,
            "Token already listed"
        );

        listingTokenPrizeId++;

        listingToken[_tokenAddress] = ListingTokenPrize({
            listingTokenPrizeId: listingTokenPrizeId,
            tokenAddress: _tokenAddress,
            isActive: true
        });

        emit ListingTokenPrizeAdded(listingTokenPrizeId, _tokenAddress, true);
    }

    function deactivateListingTokenPrize(
        address _tokenAddress
    ) external onlyOwner {
        require(
            listingToken[_tokenAddress].listingTokenPrizeId != 0,
            "Token is not listed"
        );

        require(
            listingToken[_tokenAddress].isActive,
            "Token already deactivated"
        );

        listingToken[_tokenAddress].isActive = false;

        emit ListingTokenPrizeDeactivated(
            listingToken[_tokenAddress].listingTokenPrizeId,
            _tokenAddress,
            listingToken[_tokenAddress].isActive
        );
    }

    function isTokenListed(address _tokenAddress) external view returns (bool) {
        return listingToken[_tokenAddress].listingTokenPrizeId != 0;
    }
}
