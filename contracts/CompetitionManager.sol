// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./TreasuryPlatform.sol";
import "./ListingTokenPrize.sol";
import "./PriceCompetitionManager.sol";
import "./TreasuryPrize.sol";

contract CompetitionManager is Ownable {
    TreasuryPlatform public treasuryPlatformContract;
    ListingTokenPrizeContract public listingTokenPrizeContract;
    PriceCompetitionManager public priceCompetitionManagerContract;
    TreasuryPrize public treasuryPrizeContract;

    struct CompetitionSchedule {
        uint256 registrationWindow;
        uint256 competitionWindow;
        uint256 submissionDeadline;
        uint256 judgingReview;
        uint256 resultAnnouncement;
        uint256 prizeCertificateClaim;
    }

    struct Competitions {
        uint256 id;
        string name;
        string category;
        string description;
        string requirements;
        address organization;
        CompetitionSchedule schedule;
        string certificateCID;
        string guideBookCID;
    }

    struct Winners {
        uint256 id;
        uint256 competitionId;
        string title;
        address prizeToken;
        uint256 prizeAmount;
        string certificateCID;
    }

    struct ParticipantWinner {
        uint256 id;
        uint256 winnerId;
        address participant;
    }

    uint256 private competitionId;
    uint256 private winnerId;
    uint256 private participantWinnerId;

    mapping(uint256 => Competitions) public competitions;
    mapping(uint256 => Winners[]) public winners;
    mapping(uint256 => Winners) public winnerById;
    mapping(uint256 => ParticipantWinner[]) public participantWinner;
    mapping(uint256 => uint256) public competitionTotalPrize;

    event CompetitionCreated(
        uint256 indexed id,
        address indexed organization,
        Competitions competition,
        Winners[] winners,
        uint256 priceCompetitionFeeId
    );

    event WinnerSet(
        uint256 indexed winnerId,
        address indexed participant,
        uint256 indexed competitionId,
        uint256 participantWinnerId,
        string title
    );

    event CompetitionFeePaid(
        uint256 indexed competitionId,
        address indexed payer,
        address indexed tokenAddress,
        uint256 amount
    );

    modifier onlyOrganization(
        address _address_organization,
        uint256 _competition_id
    ) {
        require(
            competitions[_competition_id].id != 0,
            "Competition does not exist"
        );
        require(
            competitions[_competition_id].organization == _address_organization,
            "Not organization"
        );
        _;
    }

    modifier onlyCompetitionEnd(uint256 _competitionId) {
        require(
            competitions[_competitionId].id != 0,
            "Competition does not exist"
        );
        require(
            block.timestamp >=
                competitions[_competitionId].schedule.prizeCertificateClaim,
            "Competition is not ended"
        );
        _;
    }

    constructor(
        address initialOwner,
        address _priceCompetitionManagerAddress,
        address payable _treasuryPlatformAddress,
        address _listingTokenPrizeAddress,
        address payable _treasuryPrizeAddress
    ) Ownable(initialOwner) {
        priceCompetitionManagerContract = PriceCompetitionManager(
            _priceCompetitionManagerAddress
        );
        treasuryPlatformContract = TreasuryPlatform(_treasuryPlatformAddress);
        listingTokenPrizeContract = ListingTokenPrizeContract(
            _listingTokenPrizeAddress
        );
        treasuryPrizeContract = TreasuryPrize(_treasuryPrizeAddress);
    }

    function createCompetition(
        Competitions calldata _competition,
        Winners[] calldata _winners,
        uint256 _priceCompetitionFeeId
    ) external payable {
        require(
            _competition.schedule.prizeCertificateClaim > block.timestamp,
            "Invalid end time"
        );
        require(_winners.length > 0, "Must have at least one winner");

        address sender = _competition.organization == address(0)
            ? msg.sender
            : _competition.organization;

        competitionId++;

        competitions[competitionId] = _competition;
        competitions[competitionId].id = competitionId;
        competitions[competitionId].organization = sender;

        PriceCompetitionManager.PriceCompetitionFee
            memory platformFee = priceCompetitionManagerContract
                .getPriceCompetitionFee(_priceCompetitionFeeId);

        require(platformFee.id != 0, "Fee option does not exist");

        uint256 fee = platformFee.treasuryFee;
        address feeToken = platformFee.tokenAddress;
        uint256 totalPrizeAmount = 0;
        address firstPrizeToken = _winners[0].prizeToken;

        for (uint256 i = 0; i < _winners.length; i++) {
            require(
                _winners[i].prizeAmount > 0,
                "Prize must be greater than 0"
            );
            require(
                _winners[i].prizeToken == firstPrizeToken,
                "Prize token must be the same for all winners"
            );

            (
                ,
                address listedTokenAddress,
                bool isPrizeTokenActive
            ) = listingTokenPrizeContract.listingToken(_winners[i].prizeToken);

            require(
                listedTokenAddress == _winners[i].prizeToken,
                "Prize token is not listed"
            );
            require(isPrizeTokenActive, "Prize token is not active");

            totalPrizeAmount += _winners[i].prizeAmount;

            winnerId++;
            Winners memory newWinner = Winners({
                id: winnerId,
                competitionId: competitionId,
                title: _winners[i].title,
                prizeToken: _winners[i].prizeToken,
                prizeAmount: _winners[i].prizeAmount,
                certificateCID: _winners[i].certificateCID
            });

            winners[competitionId].push(newWinner);
            winnerById[winnerId] = newWinner;
        }

        competitionTotalPrize[competitionId] = totalPrizeAmount;

        emit CompetitionCreated(
            competitionId,
            sender,
            competitions[competitionId],
            winners[competitionId],
            _priceCompetitionFeeId
        );

        uint256 requiredNative = 0;
        if (fee > 0 && feeToken == address(0)) {
            requiredNative += fee;
        }
        if (firstPrizeToken == address(0)) {
            requiredNative += totalPrizeAmount;
        }

        require(msg.value == requiredNative, "Incorrect native amount");

        if (fee > 0) {
            if (feeToken == address(0)) {
                treasuryPlatformContract.addTreasuryFrom{value: fee}(
                    sender,
                    address(0),
                    fee
                );
            } else {
                treasuryPlatformContract.addTreasuryFrom(sender, feeToken, fee);
            }
            emit CompetitionFeePaid(competitionId, sender, feeToken, fee);
        }

        if (totalPrizeAmount > 0) {
            uint256 nativePrizeValue = firstPrizeToken == address(0)
                ? totalPrizeAmount
                : 0;
            treasuryPrizeContract.addTreasury{value: nativePrizeValue}(
                TreasuryPrize.TreasuryPrize({
                    id: 0,
                    competitionId: competitionId,
                    organization: sender,
                    totalPrize: totalPrizeAmount,
                    tokenAddress: firstPrizeToken
                }),
                sender
            );
        }
    }

    function setWinner(
        uint256 _winnerId,
        address _participant,
        uint256 _competition_id
    ) external onlyOrganization(msg.sender, _competition_id) {
        require(winnerById[_winnerId].id != 0, "Winner does not exist");
        require(
            winnerById[_winnerId].competitionId == _competition_id,
            "Winner does not belong to this competition"
        );

        Winners memory winner_participant = winnerById[_winnerId];

        require(
            competitionTotalPrize[_competition_id] >=
                winner_participant.prizeAmount,
            "Insufficient competition prize balance"
        );

        competitionTotalPrize[_competition_id] -= winner_participant
            .prizeAmount;

        participantWinnerId++;

        participantWinner[_winnerId].push(
            ParticipantWinner({
                id: participantWinnerId,
                winnerId: _winnerId,
                participant: _participant
            })
        );
        treasuryPrizeContract.payout(
            _competition_id,
            payable(_participant),
            winner_participant.prizeAmount,
            winner_participant.prizeToken,
            msg.sender
        );

        emit WinnerSet(
            _winnerId,
            _participant,
            _competition_id,
            participantWinnerId,
            winner_participant.title
        );
    }

    function getCompetition(
        uint256 _competitionId
    ) external view returns (Competitions memory) {
        return competitions[_competitionId];
    }

    function getCompetitionsByOrganization(
        address _organization
    ) external view returns (Competitions[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= competitionId; i++) {
            if (competitions[i].organization == _organization) {
                count++;
            }
        }

        Competitions[] memory result = new Competitions[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= competitionId; i++) {
            if (competitions[i].organization == _organization) {
                result[index] = competitions[i];
                index++;
            }
        }

        return result;
    }

    function getAllCompetitions()
        external
        view
        returns (Competitions[] memory)
    {
        Competitions[] memory result = new Competitions[](competitionId);
        for (uint256 i = 1; i <= competitionId; i++) {
            result[i - 1] = competitions[i];
        }
        return result;
    }

    function getWinners(
        uint256 _competitionId
    ) external view returns (Winners[] memory) {
        return winners[_competitionId];
    }

    function getWinner(
        uint256 _winnerId
    ) external view returns (Winners memory) {
        require(winnerById[_winnerId].id != 0, "Winner does not exist");
        return winnerById[_winnerId];
    }

    function getParticipantWinners(
        uint256 _winnerId
    ) external view returns (ParticipantWinner[] memory) {
        return participantWinner[_winnerId];
    }

    function isCompetitionEnded(
        uint256 _competitionId
    ) external view returns (bool) {
        return
            block.timestamp >=
            competitions[_competitionId].schedule.prizeCertificateClaim;
    }
}
