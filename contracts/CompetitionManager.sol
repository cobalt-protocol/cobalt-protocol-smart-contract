// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./TreasuryPlatform.sol";
import "./ListingTokenPrize.sol";
import "./PriceCompetitionManager.sol";

contract CompetitionManager is Ownable {
    TreasuryPlatform public treasuryPlatformContract;

    ListingTokenPrizeContract public listingTokenPrizeContract;

    PriceCompetitionManager public priceCompetitionManagerContract;

    struct Competitions {
        uint256 id;
        string name;
        string category;
        string description;
        string requirements;
        address organization;
        uint256 endAt;
        string certificateCID;
        string guideBookCID;
    }

    struct Winners {
        uint256 competitionId;
        uint256 winnerId;
        string title;
        address prizeToken;
        uint256 prizeAmount;
        string certificateCID;
    }

    struct ParticipantWinner {
        uint256 participantWinnerId;
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

    event CompetitionCreated(
        uint256 indexed id,
        address indexed organization,
        string name,
        string category,
        uint256 endAt,
        string certificateCID
    );

    event WinnerSet(
        uint256 indexed winnerId,
        address indexed participant,
        uint256 indexed competitionId,
        uint256 participantWinnerId
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
            block.timestamp >= competitions[_competitionId].endAt,
            "Competition is not ended"
        );

        _;
    }

    constructor(
        address initialOwner,
        address _priceCompetitionManagerAddress,
        address payable _treasuryPlatformAddress,
        address _listingTokenPrizeAddress
    ) Ownable(initialOwner) {
        priceCompetitionManagerContract = PriceCompetitionManager(
            _priceCompetitionManagerAddress
        );
        treasuryPlatformContract = TreasuryPlatform(_treasuryPlatformAddress);
        listingTokenPrizeContract = ListingTokenPrizeContract(
            _listingTokenPrizeAddress
        );
    }

    function createCompetition(
        Competitions calldata _competition,
        Winners[] calldata _winners,
        uint256 _priceCompetitionFeeId
    ) external payable {
        require(_competition.endAt > block.timestamp, "Invalid end time");

        require(_winners.length > 0, "Must have at least one winner");

        PriceCompetitionManager.PriceCompetitionFee
            memory platformFee = priceCompetitionManagerContract
                .getPriceCompetitionFee(_priceCompetitionFeeId);

        require(platformFee.id != 0, "Fee option does not exist");

        uint256 fee = platformFee.treasuryFee;
        address feeToken = platformFee.tokenAddress;

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
        }

        competitionId++;

        if (fee > 0) {
            if (feeToken == address(0)) {
                require(msg.value == fee, "Incorrect native fee");

                treasuryPlatformContract.addTreasuryFrom{value: fee}(
                    msg.sender,
                    address(0),
                    fee
                );
            } else {
                require(msg.value == 0, "Do not send native token");

                treasuryPlatformContract.addTreasuryFrom(
                    msg.sender,
                    feeToken,
                    fee
                );
            }

            emit CompetitionFeePaid(competitionId, msg.sender, feeToken, fee);
        } else {
            require(msg.value == 0, "Do not send native token");
        }

        competitions[competitionId] = Competitions({
            id: competitionId,
            name: _competition.name,
            category: _competition.category,
            description: _competition.description,
            requirements: _competition.requirements,
            organization: msg.sender,
            endAt: _competition.endAt,
            certificateCID: _competition.certificateCID,
            guideBookCID: _competition.guideBookCID
        });

        for (uint256 i = 0; i < _winners.length; i++) {
            winnerId++;

            Winners memory newWinner = Winners({
                competitionId: competitionId,
                winnerId: winnerId,
                title: _winners[i].title,
                prizeToken: _winners[i].prizeToken,
                prizeAmount: _winners[i].prizeAmount,
                certificateCID: _winners[i].certificateCID
            });

            winners[competitionId].push(newWinner);

            winnerById[winnerId] = newWinner;
        }

        emit CompetitionCreated(
            competitionId,
            msg.sender,
            _competition.name,
            _competition.category,
            _competition.endAt,
            _competition.certificateCID
        );
    }

    function setWinner(
        uint256 _winnerId,
        address _participant,
        uint256 _competition_id
    ) external payable onlyOrganization(msg.sender, _competition_id) {
        participantWinnerId++;

        require(winnerById[_winnerId].winnerId != 0, "Winner does not exist");

        participantWinner[_winnerId].push(
            ParticipantWinner({
                participantWinnerId: participantWinnerId,
                winnerId: _winnerId,
                participant: _participant
            })
        );

        Winners memory winner_participant = winnerById[_winnerId];
        if (winner_participant.prizeToken == address(0)) {
            require(
                msg.value == winner_participant.prizeAmount,
                "Incorrect native amount"
            );

            (bool success, ) = payable(_participant).call{
                value: winner_participant.prizeAmount
            }("");
            require(success, "Transfer failed");
        } else {
            require(msg.value == 0, "Do not send native token");

            bool success = IERC20(winner_participant.prizeToken).transfer(
                _participant,
                winner_participant.prizeAmount
            );
            require(success, "Transfer failed");
        }

        emit WinnerSet(
            _winnerId,
            _participant,
            _competition_id,
            participantWinnerId
        );
    }

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
        require(winnerById[_winnerId].winnerId != 0, "Winner does not exist");

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
        return block.timestamp >= competitions[_competitionId].endAt;
    }
}
