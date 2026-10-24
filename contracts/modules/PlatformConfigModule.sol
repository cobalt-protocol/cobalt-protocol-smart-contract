// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ManagerStorage} from "./ManagerStorage.sol";
import {CompetitionHelper} from "../helpers/CompetitionHelper.sol";

/// @title PlatformConfigModule
/// @notice Admin: signer, token listing, dan platform fee options.
abstract contract PlatformConfigModule is ManagerStorage {
    error TokenAlreadyListed();
    error TokenAlreadyDeactivated();
    error PriceFeeNotFound();

    uint256 private priceCompetitionFeeId;
    uint256 private listingTokenId;

    event PriceCompetitionFeeSet(
        uint256 indexed id,
        uint256 treasuryFee,
        address indexed tokenAddress,
        string cid
    );

    event PriceCompetitionFeeUpdated(
        uint256 indexed id,
        uint256 treasuryFee,
        address indexed tokenAddress,
        string cid
    );

    event ListingTokenAdded(
        uint256 indexed listingTokenId,
        address indexed tokenAddress,
        bool isActive
    );

    event ListingTokenDeactivated(
        uint256 indexed listingTokenId,
        address indexed tokenAddress,
        bool isActive
    );

    // ------------------------- ADMIN -------------------------

    function updateSignerAddress(address _signerAddress) external onlyOwner {
        signerAddress = _signerAddress;
    }

    function addListingToken(address _tokenAddress) external onlyOwner {
        if (listingToken[_tokenAddress].id != 0) revert TokenAlreadyListed();

        listingTokenId++;
        listingToken[_tokenAddress] = CompetitionHelper.ListingToken({
            id: listingTokenId,
            tokenAddress: _tokenAddress,
            isActive: true
        });

        emit ListingTokenAdded(listingTokenId, _tokenAddress, true);
    }

    function deactivateListingToken(address _tokenAddress) external onlyOwner {
        if (listingToken[_tokenAddress].id == 0)
            revert CompetitionHelper.TokenNotListed();
        if (!listingToken[_tokenAddress].isActive)
            revert TokenAlreadyDeactivated();

        listingToken[_tokenAddress].isActive = false;

        emit ListingTokenDeactivated(
            listingToken[_tokenAddress].id,
            _tokenAddress,
            false
        );
    }

    function setPriceCompetitionFee(
        uint256 _treasuryFee,
        address _tokenAddress,
        string calldata _cid
    ) external onlyOwner {
        CompetitionHelper.requireTokenActive(listingToken[_tokenAddress]);

        priceCompetitionFeeId++;
        priceCompetitionFees[priceCompetitionFeeId] = PriceCompetitionFee({
            id: priceCompetitionFeeId,
            treasuryFee: _treasuryFee,
            tokenAddress: _tokenAddress,
            cid: _cid
        });

        emit PriceCompetitionFeeSet(
            priceCompetitionFeeId,
            _treasuryFee,
            _tokenAddress,
            _cid
        );
    }

    function updatePriceCompetitionFee(
        uint256 _priceCompetitionFeeId,
        uint256 _treasuryFee,
        address _tokenAddress,
        string calldata _cid
    ) external onlyOwner {
        CompetitionHelper.requireTokenActive(listingToken[_tokenAddress]);

        if (priceCompetitionFees[_priceCompetitionFeeId].id == 0)
            revert PriceFeeNotFound();

        PriceCompetitionFee storage fee = priceCompetitionFees[
            _priceCompetitionFeeId
        ];
        fee.treasuryFee = _treasuryFee;
        fee.tokenAddress = _tokenAddress;
        fee.cid = _cid;

        emit PriceCompetitionFeeUpdated(
            _priceCompetitionFeeId,
            _treasuryFee,
            _tokenAddress,
            _cid
        );
    }

    // ------------------------- VIEWS -------------------------

    function isTokenListed(address _tokenAddress) external view returns (bool) {
        return listingToken[_tokenAddress].id != 0;
    }

    function isTokenActive(address _tokenAddress) external view returns (bool) {
        return listingToken[_tokenAddress].isActive;
    }

    function getPriceCompetitionFee(
        uint256 _priceCompetitionFeeId
    ) external view returns (PriceCompetitionFee memory) {
        return priceCompetitionFees[_priceCompetitionFeeId];
    }
}

