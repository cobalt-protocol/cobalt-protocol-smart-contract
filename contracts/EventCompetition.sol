// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract EventCompetition is ERC721, Ownable, ReentrancyGuard {
    struct Prize {
        uint8 rank;
        string title;
        uint256 amount;
        string winnerCertCID;
    }

    struct PrizeInput {
        uint8 rank;
        string title;
        uint256 amount;
        string winnerCertCID;
    }

    struct CompetitionInput {
        string title;
        string category;
        string description;
        string participationRequirement;
        uint256 durationInDays;
        string guidebookCID;
        string participantCertCID;
    }

    struct Competition {
        uint256 id;
        address organizer;
        string title;
        string category;
        string description;
        string participationRequirement;
        uint256 startTime;
        uint256 endTime;
        string guidebookCID;
        string participantCertCID;
        Prize[] prizes;
        bool isFinalized;
    }

    uint256 public competitionFee;
    uint256 public nextCompetitionId;
    uint256 public nextTokenId;

    mapping(uint256 => Competition) public competitions;
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => mapping(address => bool)) public isParticipant;
    mapping(uint256 => mapping(uint8 => address)) public winners;
    mapping(uint256 => mapping(address => bool)) public participantCertClaimed;
    mapping(uint256 => mapping(uint8 => bool)) public winnerCertClaimed;
    mapping(uint256 => string) public tokenCID;

    event CompetitionCreated(
        uint256 indexed competitionId,
        address indexed organizer,
        string title,
        uint256 prizePool,
        uint256 fee
    );
    event ParticipantRegistered(
        uint256 indexed competitionId,
        address indexed participant
    );
    event WinnerSet(
        uint256 indexed competitionId,
        uint8 indexed rank,
        string title,
        address indexed winner,
        uint256 prize
    );
    event CertificateMinted(
        uint256 indexed tokenId,
        uint256 indexed competitionId,
        address indexed recipient,
        string cid,
        string certType
    );
    event CompetitionFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeTransferred(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    constructor()
        ERC721("Competition Certificate", "CERT")
        Ownable(msg.sender)
    {
        competitionFee = 0.01 ether;
        nextCompetitionId = 1;
        nextTokenId = 1;
    }

    // ============ Owner ============

    function setCompetitionFee(uint256 _newFee) external onlyOwner {
        uint256 oldFee = competitionFee;
        competitionFee = _newFee;
        emit CompetitionFeeUpdated(oldFee, _newFee);
    }

    // ============ Organizer ============

    function createCompetition(
        CompetitionInput calldata _input,
        PrizeInput[] calldata _prizes
    ) external payable nonReentrant returns (uint256) {
        uint256 fee = competitionFee;
        require(msg.value >= fee, "Insufficient fee");

        uint256 n = _prizes.length;
        require(n > 0, "No prizes");
        require(_input.durationInDays > 0, "Invalid duration");
        require(
            bytes(_input.participantCertCID).length > 0,
            "Missing participant CID"
        );

        uint256 totalPrizePool;
        for (uint256 i = 0; i < n; i++) {
            require(bytes(_prizes[i].title).length > 0, "Empty prize title");
            require(
                bytes(_prizes[i].winnerCertCID).length > 0,
                "Empty winner cert CID"
            );
            totalPrizePool += _prizes[i].amount;
        }
        require(
            msg.value >= fee + totalPrizePool,
            "Insufficient for prizes+fee"
        );

        // Transfer fee langsung ke owner
        if (fee > 0) {
            (bool feeOk, ) = payable(owner()).call{value: fee}("");
            require(feeOk, "Fee transfer failed");
            emit FeeTransferred(msg.sender, owner(), fee);
        }

        // Refund kelebihan
        uint256 excess = msg.value - fee - totalPrizePool;
        if (excess > 0) {
            (bool refundOk, ) = payable(msg.sender).call{value: excess}("");
            require(refundOk, "Refund failed");
        }

        // Simpan competition
        uint256 competitionId = nextCompetitionId++;
        Competition storage comp = competitions[competitionId];
        comp.id = competitionId;
        comp.organizer = msg.sender;
        comp.title = _input.title;
        comp.category = _input.category;
        comp.description = _input.description;
        comp.participationRequirement = _input.participationRequirement;
        comp.startTime = block.timestamp;
        comp.endTime = block.timestamp + (_input.durationInDays * 1 days);
        comp.guidebookCID = _input.guidebookCID;
        comp.participantCertCID = _input.participantCertCID;

        for (uint256 i = 0; i < n; i++) {
            comp.prizes.push(
                Prize({
                    rank: _prizes[i].rank,
                    title: _prizes[i].title,
                    amount: _prizes[i].amount,
                    winnerCertCID: _prizes[i].winnerCertCID
                })
            );
        }

        emit CompetitionCreated(
            competitionId,
            msg.sender,
            _input.title,
            totalPrizePool,
            fee
        );
        return competitionId;
    }

    function registerAsParticipant(uint256 _competitionId) external {
        Competition storage comp = competitions[_competitionId];
        require(comp.id != 0, "Not exist");
        require(block.timestamp < comp.endTime, "Ended");
        require(
            !isParticipant[_competitionId][msg.sender],
            "Already registered"
        );
        require(comp.organizer != msg.sender, "Organizer cannot join");

        isParticipant[_competitionId][msg.sender] = true;
        participants[_competitionId].push(msg.sender);

        emit ParticipantRegistered(_competitionId, msg.sender);
    }

    function setWinners(
        uint256 _competitionId,
        uint8[] calldata _ranks,
        address[] calldata _winnerAddresses
    ) external nonReentrant {
        Competition storage comp = competitions[_competitionId];
        require(comp.id != 0, "Not exist");
        require(msg.sender == comp.organizer, "Only organizer");
        require(!comp.isFinalized, "Finalized");
        require(block.timestamp >= comp.endTime, "Still ongoing");
        require(_ranks.length == _winnerAddresses.length, "Length mismatch");
        require(_ranks.length == comp.prizes.length, "Must set all ranks");

        for (uint256 i = 0; i < _ranks.length; i++) {
            _setWinner(comp, _competitionId, _ranks[i], _winnerAddresses[i]);
        }

        comp.isFinalized = true;
    }

    function _setWinner(
        Competition storage comp,
        uint256 _competitionId,
        uint8 _rank,
        address _winner
    ) internal {
        require(_winner != address(0), "Invalid winner");
        require(isParticipant[_competitionId][_winner], "Not participant");
        require(winners[_competitionId][_rank] == address(0), "Rank assigned");

        uint256 prizeAmount;
        string memory prizeTitle;
        for (uint256 j = 0; j < comp.prizes.length; j++) {
            if (comp.prizes[j].rank == _rank) {
                prizeAmount = comp.prizes[j].amount;
                prizeTitle = comp.prizes[j].title;
                break;
            }
        }

        winners[_competitionId][_rank] = _winner;

        if (prizeAmount > 0) {
            (bool ok, ) = payable(_winner).call{value: prizeAmount}("");
            require(ok, "Prize transfer failed");
        }

        emit WinnerSet(_competitionId, _rank, prizeTitle, _winner, prizeAmount);
    }

    // ============ User ============

    function claimParticipantCertificate(
        uint256 _competitionId
    ) external nonReentrant {
        Competition storage comp = competitions[_competitionId];
        require(comp.id != 0, "Not exist");
        require(comp.isFinalized, "Not finalized");
        require(isParticipant[_competitionId][msg.sender], "Not participant");
        require(!participantCertClaimed[_competitionId][msg.sender], "Claimed");

        participantCertClaimed[_competitionId][msg.sender] = true;

        uint256 tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);
        tokenCID[tokenId] = comp.participantCertCID;

        emit CertificateMinted(
            tokenId,
            _competitionId,
            msg.sender,
            comp.participantCertCID,
            "participant"
        );
    }

    function claimWinnerCertificate(
        uint256 _competitionId,
        uint8 _rank
    ) external nonReentrant {
        Competition storage comp = competitions[_competitionId];
        require(comp.id != 0, "Not exist");
        require(comp.isFinalized, "Not finalized");
        require(winners[_competitionId][_rank] == msg.sender, "Not winner");
        require(!winnerCertClaimed[_competitionId][_rank], "Claimed");

        string memory cid;
        for (uint256 i = 0; i < comp.prizes.length; i++) {
            if (comp.prizes[i].rank == _rank) {
                cid = comp.prizes[i].winnerCertCID;
                break;
            }
        }
        require(bytes(cid).length > 0, "No cert CID");

        winnerCertClaimed[_competitionId][_rank] = true;

        uint256 tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);
        tokenCID[tokenId] = cid;

        emit CertificateMinted(
            tokenId,
            _competitionId,
            msg.sender,
            cid,
            "winner"
        );
    }

    // ============ View ============

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked("ipfs://", tokenCID[tokenId]));
    }

    function getPrizes(
        uint256 _competitionId
    ) external view returns (Prize[] memory) {
        return competitions[_competitionId].prizes;
    }

    function getParticipants(
        uint256 _competitionId
    ) external view returns (address[] memory) {
        return participants[_competitionId];
    }

    function getPrizeByRank(
        uint256 _competitionId,
        uint8 _rank
    ) external view returns (Prize memory) {
        Competition storage comp = competitions[_competitionId];
        for (uint256 i = 0; i < comp.prizes.length; i++) {
            if (comp.prizes[i].rank == _rank) {
                return comp.prizes[i];
            }
        }
        revert("Rank not found");
    }
}
