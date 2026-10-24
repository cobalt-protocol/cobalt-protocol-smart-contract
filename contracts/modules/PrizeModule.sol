// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ManagerStorage} from "./ManagerStorage.sol";
import {CompetitionHelper} from "../helpers/CompetitionHelper.sol";

/// @title PrizeModule
/// @notice Pencatatan pemenang (setWinner) dan distribusi hadiah (distributePrizes).
abstract contract PrizeModule is ManagerStorage {
    error TreasuryDoesNotExist();
    error InvalidRecipient();
    error WinnerDoesNotExist();
    error WinnerMismatch();
    error NotAllWinnersRecorded();
    error DistributePeriodExpired();

    event WinnerSet(
        uint256 indexed winnerId,
        address indexed participant,
        uint256 indexed competitionId,
        string teamId,
        bytes signature
    );

    event PrizeDistributed(
        uint256 indexed treasuryPrizeId,
        uint256 indexed competitionId,
        address indexed tokenAddress,
        address recipient,
        uint256 amount
    );

    event PrizesDistributed(
        uint256 indexed competitionId,
        uint256 totalWinners
    );

    /**
     * @notice Hanya mencatat pemenang. Hadiah BELUM ditransfer.
     * Hadiah akan didistribusikan melalui distributePrizes()
     * setelah SEMUA pemenang pada kompetisi tersebut sudah dicatat.
     */
    function setWinner(
        uint256 _winnerId,
        address _participant,
        uint256 _competitionId,
        string calldata _teamId,
        bytes calldata _signature
    ) external onlyCompetitionEnd(_competitionId) {
        Winners memory w = winnerById[_winnerId];

        if (w.id == 0) revert WinnerDoesNotExist();
        if (w.competitionId != _competitionId) revert WinnerMismatch();
        if (bytes(_teamId).length == 0) revert InvalidTeamId();
        if (_participant == address(0)) revert InvalidRecipient();

        CompetitionHelper.verifySig(
            keccak256(
                abi.encodePacked(
                    address(this),
                    _winnerId,
                    _participant,
                    _competitionId,
                    _teamId
                )
            ),
            _signature,
            signerAddress
        );

        // Catat pemenang
        if (bytes(winnerTeamId[_winnerId]).length == 0) {
            winnersSetCount[_competitionId]++;
        }
        winnerParticipant[_competitionId][_teamId] = _participant;
        winnerTeamId[_winnerId] = _teamId;

        emit WinnerSet(
            _winnerId,
            _participant,
            _competitionId,
            _teamId,
            _signature
        );
    }

    /**
     * @notice Distribusikan hadiah ke SEMUA pemenang setelah semua sudah dicatat.
     */
    function distributePrizes(
        uint256 _competitionId
    ) external onlyCompetitionEnd(_competitionId) {
        if (prizesDistributed[_competitionId])
            revert PrizesAlreadyDistributed();

        uint256 competitionEndTime = competitions[_competitionId]
            .prizeCertificateClaim;
        if (block.timestamp > competitionEndTime + 7 days) {
            revert DistributePeriodExpired();
        }

        Winners[] memory allWinners = winners[_competitionId];
        uint256 totalWinners = allWinners.length;

        if (totalWinners == 0) revert MustHaveWinner();
        if (winnersSetCount[_competitionId] < totalWinners) {
            revert NotAllWinnersRecorded();
        }

        TreasuryPrize storage compPrize = treasuryPrizeByCompetitionId[
            _competitionId
        ];
        if (compPrize.organization == address(0)) {
            revert TreasuryDoesNotExist();
        }

        // Tandai sudah didistribusikan sebelum external call (CEI)
        prizesDistributed[_competitionId] = true;

        for (uint256 i; i < totalWinners; ++i) {
            Winners memory w = allWinners[i];
            address participant = winnerParticipant[_competitionId][
                winnerTeamId[w.id]
            ];

            if (participant == address(0)) revert WinnerDoesNotExist();
            if (w.prizeAmount == 0) revert AmountZero();
            if (compPrize.totalPrize < w.prizeAmount)
                revert InsufficientPrizeBalance();
            if (compPrize.tokenAddress != w.prizeToken)
                revert PrizeTokenMismatch();

            // Update balance
            competitionTotalPrize[_competitionId] -= w.prizeAmount;
            compPrize.totalPrize -= w.prizeAmount;

            // Transfer
            if (w.prizeToken == address(0)) {
                (bool ok, ) = payable(participant).call{value: w.prizeAmount}(
                    ""
                );
                if (!ok) revert TransferFailed();
            } else {
                if (!IERC20(w.prizeToken).transfer(participant, w.prizeAmount))
                    revert TransferFailed();
            }

            emit PrizeDistributed(
                _competitionId,
                _competitionId,
                w.prizeToken,
                participant,
                w.prizeAmount
            );
        }

        emit PrizesDistributed(_competitionId, totalWinners);
    }

    // ------------------------- VIEWS -------------------------

    function isAllWinnersRecorded(
        uint256 _competitionId
    ) external view returns (bool) {
        return
            winnersSetCount[_competitionId] >= winners[_competitionId].length;
    }

    function getWinnerParticipant(
        uint256 _competitionId,
        string calldata _teamId
    ) external view returns (address) {
        return winnerParticipant[_competitionId][_teamId];
    }

    function getWinnersSetCount(
        uint256 _competitionId
    ) external view returns (uint256) {
        return winnersSetCount[_competitionId];
    }
}

