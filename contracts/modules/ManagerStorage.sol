// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CompetitionHelper} from "../helpers/CompetitionHelper.sol";

/// @title ManagerStorage
/// @notice Shared types, errors, storage, and modifiers for all CompetitionManager modules.
/// @dev Abstract: all modules are merged into ONE deployed contract (CompetitionManager),
///      so storage is shared via inheritance (no external calls between modules).
abstract contract ManagerStorage is Ownable {
    // =============================================================
    //                      SHARED ERRORS
    // =============================================================

    error AmountZero();
    error IncorrectNativeAmount();
    error TransferFailed();
    error InsufficientPrizeBalance();
    error MustHaveWinner();
    error PrizeTokenMismatch();
    error InvalidTeamId();
    error CompetitionDoesNotExist();
    error CompetitionNotEnded();
    error PrizesAlreadyDistributed();
    error PrizesNotDistributed();

    // Legacy (declared in the original contract, currently unused)
    error IncorrectFeeAmount();
    error InsufficientCompetitionPrize();
    error NotOrganization();

    // =============================================================
    //                      STRUCTS
    // =============================================================

    struct CompetitionPayment {
        address tokenAddress;
        uint256 fee;
    }

    struct Competitions {
        uint256 id;
        string cid;
        string formation;
        address organization;
        uint256 prizeCertificateClaim;
        string certificateCID;
        CompetitionPayment payment;
    }

    struct Winners {
        uint256 id;
        uint256 competitionId;
        address prizeToken;
        uint256 prizeAmount;
        string certificateCID;
    }

    struct PriceCompetitionFee {
        uint256 id;
        uint256 treasuryFee;
        address tokenAddress;
        string cid;
    }

    struct TreasuryPrize {
        uint256 id;
        uint256 competitionId;
        address organization;
        uint256 totalPrize;
        address tokenAddress;
    }

    // =============================================================
    //                      SHARED STORAGE
    // =============================================================

    address internal signerAddress;

    mapping(uint256 => Competitions) internal competitions;
    mapping(uint256 => Winners[]) internal winners;
    mapping(uint256 => Winners) internal winnerById;
    mapping(uint256 => uint256) internal competitionTotalPrize;
    mapping(uint256 => PriceCompetitionFee) internal priceCompetitionFees;
    mapping(address => CompetitionHelper.ListingToken) internal listingToken;
    mapping(uint256 => TreasuryPrize) internal treasuryPrizeByCompetitionId;
    mapping(uint256 => mapping(address => uint256)) internal totalPaid;

    mapping(uint256 => mapping(address => bool))
        internal winnerParticipantClaimed;

    mapping(uint256 => address) internal winnerParticipant; // winnerId => participant
    mapping(uint256 => string) internal winnerTeamId; // winnerId => teamId
    mapping(uint256 => uint256) internal winnersSetCount; // competitionId => jumlah winner dicatat
    mapping(uint256 => bool) internal prizesDistributed; // competitionId => sudah didistribusikan?

    // =============================================================
    //                      MODIFIERS
    // =============================================================

    modifier competitionExists(uint256 _competitionId) {
        if (competitions[_competitionId].id == 0)
            revert CompetitionDoesNotExist();
        _;
    }

    /// @dev Cek apakah _competitionId valid ada di storage competitions
    modifier onlyOrganization(uint256 _competitionId) {
        if (competitions[_competitionId].id == 0)
            revert CompetitionDoesNotExist();
        _;
    }

    modifier onlyCompetitionEnd(uint256 _competitionId) {
        if (competitions[_competitionId].id == 0)
            revert CompetitionDoesNotExist();
        if (
            block.timestamp < competitions[_competitionId].prizeCertificateClaim
        ) revert CompetitionNotEnded();
        _;
    }
}

