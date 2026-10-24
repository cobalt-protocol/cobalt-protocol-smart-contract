// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ManagerStorage} from "./ManagerStorage.sol";
import {CompetitionHelper} from "../helpers/CompetitionHelper.sol";
import {FormationHelper} from "../helpers/FormationHelper.sol";

/// @title CompetitionCreationModule
/// @notice Pembuatan kompetisi (+ platform fee & prize escrow) dan getter kompetisi.
abstract contract CompetitionCreationModule is ManagerStorage {
    error InvalidFormation();
    error InvalidEndTime();
    error FeeOptionNotFound();
    error PrizeAmountZero();

    uint256 private competitionId;
    uint256 private winnerId;

    event CompetitionCreated(
        uint256 indexed id,
        address indexed organization,
        string cid,
        string formation,
        uint256 prizeCertificateClaim,
        string certificateCID,
        uint256 priceCompetitionFeeId,
        bytes signature
    );

    event CompetitionPaymentConfigured(
        uint256 indexed competitionId,
        address indexed tokenAddress,
        uint256 fee
    );

    event CompetitionWinnerConfigured(
        uint256 indexed competitionId,
        uint256 indexed winnerId,
        address prizeToken,
        uint256 prizeAmount,
        string certificateCID
    );

    event CompetitionFeePaid(
        uint256 indexed competitionId,
        address indexed payer,
        address indexed tokenAddress,
        uint256 amount
    );

    event TreasuryAdded(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event PrizeDeposited(
        uint256 indexed treasuryPrizeId,
        uint256 indexed competitionId,
        address indexed tokenAddress,
        address sender,
        uint256 amount
    );

    function createCompetition(
        Competitions calldata _competition,
        CompetitionPayment calldata _payment,
        Winners[] calldata _winners,
        uint256 _priceCompetitionFeeId,
        bytes calldata _signature
    ) external payable {
        if (_competition.prizeCertificateClaim <= block.timestamp)
            revert InvalidEndTime();
        if (!FormationHelper.isValidFormation(_competition.formation))
            revert InvalidFormation();
        if (_winners.length == 0) revert MustHaveWinner();

        CompetitionHelper.verifySig(
            keccak256(
                abi.encode(
                    address(this),
                    _competition,
                    _payment,
                    _winners,
                    _priceCompetitionFeeId
                )
            ),
            _signature,
            signerAddress
        );

        CompetitionHelper.requireTokenActive(
            listingToken[_payment.tokenAddress]
        );
        if (priceCompetitionFees[_priceCompetitionFeeId].id == 0)
            revert FeeOptionNotFound();

        uint256 newId = ++competitionId;
        {
            address sender = _competition.organization == address(0)
                ? msg.sender
                : _competition.organization;

            competitions[newId] = _competition;
            competitions[newId].id = newId;
            competitions[newId].organization = sender;
            competitions[newId].payment = _payment;

            emit CompetitionPaymentConfigured(
                newId,
                _payment.tokenAddress,
                _payment.fee
            );
        }

        uint256 totalPrizeAmount;
        {
            address firstPrizeToken = _winners[0].prizeToken;
            for (uint256 i; i < _winners.length; ++i) {
                if (_winners[i].prizeAmount == 0) revert PrizeAmountZero();
                if (_winners[i].prizeToken != firstPrizeToken)
                    revert PrizeTokenMismatch();

                CompetitionHelper.requireTokenActive(
                    listingToken[_winners[i].prizeToken]
                );

                totalPrizeAmount += _winners[i].prizeAmount;
                uint256 wId = ++winnerId;

                Winners memory w = Winners({
                    id: wId,
                    competitionId: newId,
                    prizeToken: _winners[i].prizeToken,
                    prizeAmount: _winners[i].prizeAmount,
                    certificateCID: _winners[i].certificateCID
                });

                winners[newId].push(w);
                winnerById[wId] = w;

                emit CompetitionWinnerConfigured(
                    newId,
                    wId,
                    w.prizeToken,
                    w.prizeAmount,
                    w.certificateCID
                );
            }
            competitionTotalPrize[newId] = totalPrizeAmount;
        }

        {
            Competitions storage comp = competitions[newId];
            emit CompetitionCreated(
                newId,
                comp.organization,
                comp.cid,
                comp.formation,
                comp.prizeCertificateClaim,
                comp.certificateCID,
                _priceCompetitionFeeId,
                _signature
            );
        }

        {
            PriceCompetitionFee storage platformFee = priceCompetitionFees[
                _priceCompetitionFeeId
            ];
            uint256 platformTreasuryFee = platformFee.treasuryFee;
            address platformFeeToken = platformFee.tokenAddress;
            address firstPrizeToken = _winners[0].prizeToken;
            address sender = competitions[newId].organization;

            uint256 requiredNative;
            if (platformTreasuryFee > 0 && platformFeeToken == address(0)) {
                requiredNative += platformTreasuryFee;
            }
            if (firstPrizeToken == address(0)) {
                requiredNative += totalPrizeAmount;
            }
            if (msg.value != requiredNative) revert IncorrectNativeAmount();

            if (platformTreasuryFee > 0) {
                address recipient = owner();
                if (platformFeeToken == address(0)) {
                    (bool ok, ) = payable(recipient).call{
                        value: platformTreasuryFee
                    }("");
                    if (!ok) revert TransferFailed();
                } else {
                    if (
                        !IERC20(platformFeeToken).transferFrom(
                            sender,
                            recipient,
                            platformTreasuryFee
                        )
                    ) revert TransferFailed();
                }
                emit TreasuryAdded(
                    platformFeeToken,
                    sender,
                    platformTreasuryFee
                );
                emit CompetitionFeePaid(
                    newId,
                    sender,
                    platformFeeToken,
                    platformTreasuryFee
                );
            }

            if (totalPrizeAmount > 0) {
                if (firstPrizeToken != address(0)) {
                    if (
                        !IERC20(firstPrizeToken).transferFrom(
                            sender,
                            address(this),
                            totalPrizeAmount
                        )
                    ) revert TransferFailed();
                }

                treasuryPrizeByCompetitionId[newId] = TreasuryPrize({
                    id: newId,
                    competitionId: newId,
                    organization: sender,
                    totalPrize: totalPrizeAmount,
                    tokenAddress: firstPrizeToken
                });

                emit PrizeDeposited(
                    newId,
                    newId,
                    firstPrizeToken,
                    sender,
                    totalPrizeAmount
                );
            }
        }
    }

    // ------------------------- VIEWS -------------------------

    function getCompetition(
        uint256 _competitionId
    ) external view returns (Competitions memory) {
        return competitions[_competitionId];
    }

    function getWinners(
        uint256 _competitionId
    ) external view returns (Winners[] memory) {
        return winners[_competitionId];
    }

    function getWinner(
        uint256 _winnerId
    ) external view returns (Winners memory) {
        return winnerById[_winnerId];
    }

    function isCompetitionEnded(
        uint256 _competitionId
    ) external view returns (bool) {
        return
            block.timestamp >=
            competitions[_competitionId].prizeCertificateClaim;
    }
}
