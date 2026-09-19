// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title EventCompetition
 * @dev Smart contract untuk event perlombaan dengan sertifikat NFT
 */
contract EventCompetition is ERC721URIStorage, Ownable, ReentrancyGuard {
    // ============ Structs ============

    struct Prize {
        string title; // "Juara 1", "Juara 2", dst.
        uint256 amount; // jumlah hadiah dalam wei
        string certCID; // CID sertifikat juara
    }

    struct Competition {
        uint256 id;
        address organizer;
        string title;
        string category;
        string description;
        string participationRequirement;
        uint256 duration; // durasi dalam detik
        uint256 startTime; // waktu mulai (saat dibuat)
        uint256 endTime; // startTime + duration
        string guidebookCID;
        string participantCertCID; // CID sertifikat untuk semua peserta
        uint256 totalPrizePool; // total hadiah yang di-deposit
        uint256 remainingPrize; // sisa hadiah yang belum diklaim pemenang
        bool winnersSet; // apakah pemenang sudah ditentukan
        bool exists;
    }

    // ============ State Variables ============

    uint256 public creationFee; // fee untuk organisasi membuat lomba
    uint256 public competitionCounter; // counter ID lomba
    uint256 private _tokenIdCounter; // counter NFT

    // competitionId => Competition
    mapping(uint256 => Competition) public competitions;

    // competitionId => Prize[] (daftar hadiah)
    mapping(uint256 => Prize[]) public competitionPrizes;

    // competitionId => list pemenang
    mapping(uint256 => address[]) public winners;

    // competitionId => apakah address adalah pemenang
    mapping(uint256 => mapping(address => bool)) public isWinner;

    // competitionId => apakah address sudah claim sertifikat peserta
    mapping(uint256 => mapping(address => bool))
        public hasClaimedParticipantCert;

    // competitionId => apakah address sudah claim sertifikat juara
    mapping(uint256 => mapping(address => bool)) public hasClaimedWinnerCert;

    // daftar semua organisasi
    mapping(address => bool) public isOrganizer;

    // ============ Events ============

    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event OrganizerRegistered(address indexed organizer);
    event CompetitionCreated(
        uint256 indexed competitionId,
        address indexed organizer,
        string title,
        uint256 totalPrizePool,
        uint256 startTime,
        uint256 endTime
    );
    event WinnerSet(
        uint256 indexed competitionId,
        address indexed winner,
        uint256 prizeAmount,
        uint256 rank
    );
    event PrizeClaimed(
        uint256 indexed competitionId,
        address indexed winner,
        uint256 amount
    );
    event CertificateClaimed(
        uint256 indexed competitionId,
        address indexed user,
        uint256 tokenId,
        string certType // "participant" atau "winner"
    );

    // ============ Constructor ============

    constructor(
        uint256 _initialCreationFee
    ) ERC721("Competition Certificate", "CERT") Ownable(msg.sender) {
        creationFee = _initialCreationFee;
    }

    // ============ Modifiers ============

    modifier onlyOrganizer() {
        require(isOrganizer[msg.sender], "Not an organizer");
        _;
    }

    modifier competitionExists(uint256 _competitionId) {
        require(competitions[_competitionId].exists, "Competition not found");
        _;
    }

    // ============ Owner Functions ============

    /**
     * @dev Owner set fee untuk pembuatan lomba
     */
    function setCreationFee(uint256 _newFee) external onlyOwner {
        uint256 oldFee = creationFee;
        creationFee = _newFee;
        emit CreationFeeUpdated(oldFee, _newFee);
    }

    /**
     * @dev Owner withdraw accumulated fees
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        // kurangi total hadiah yang masih tersimpan (belum di-claim)
        // Note: kita perlu track total hadiah yang belum diklaim
        require(balance > 0, "No fees to withdraw");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }

    // ============ Organizer Functions ============

    /**
     * @dev Membuat perlombaan baru
     * @notice Saat membuat lomba, lomba otomatis dimulai (startTime = now)
     * @param _title Judul kompetisi
     * @param _category Kategori kompetisi
     * @param _description Deskripsi kompetisi
     * @param _participationRequirement Requirement partisipasi
     * @param _duration Durasi lomba dalam detik
     * @param _prizeTitles Array nama juara (misal ["Juara 1", "Juara 2", "Juara 3"])
     * @param _prizeAmounts Array jumlah hadiah per juara
     * @param _prizeCertCIDs Array CID sertifikat juara
     * @param _guidebookCID CID guidebook
     * @param _participantCertCID CID sertifikat untuk semua peserta
     */
    function createCompetition(
        string calldata _title,
        string calldata _category,
        string calldata _description,
        string calldata _participationRequirement,
        uint256 _duration,
        string[] calldata _prizeTitles,
        uint256[] calldata _prizeAmounts,
        string[] calldata _prizeCertCIDs,
        string calldata _guidebookCID,
        string calldata _participantCertCID
    ) external payable nonReentrant returns (uint256) {
        require(msg.value >= creationFee, "Insufficient creation fee");
        require(_duration > 0, "Duration must be > 0");
        require(bytes(_title).length > 0, "Title required");
        require(_prizeTitles.length > 0, "At least 1 prize");
        require(
            _prizeTitles.length == _prizeAmounts.length &&
                _prizeTitles.length == _prizeCertCIDs.length,
            "Prize arrays length mismatch"
        );

        // Hitung total prize pool
        uint256 totalPrizePool = 0;
        for (uint256 i = 0; i < _prizeAmounts.length; i++) {
            totalPrizePool += _prizeAmounts[i];
        }

        // Pastikan msg.value cukup untuk fee + total hadiah
        require(
            msg.value >= creationFee + totalPrizePool,
            "Insufficient funds for fee + prizes"
        );

        // Auto-register sebagai organizer jika belum
        if (!isOrganizer[msg.sender]) {
            isOrganizer[msg.sender] = true;
            emit OrganizerRegistered(msg.sender);
        }

        competitionCounter++;
        uint256 competitionId = competitionCounter;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _duration;

        Competition storage comp = competitions[competitionId];
        comp.id = competitionId;
        comp.organizer = msg.sender;
        comp.title = _title;
        comp.category = _category;
        comp.description = _description;
        comp.participationRequirement = _participationRequirement;
        comp.duration = _duration;
        comp.startTime = startTime;
        comp.endTime = endTime;
        comp.guidebookCID = _guidebookCID;
        comp.participantCertCID = _participantCertCID;
        comp.totalPrizePool = totalPrizePool;
        comp.remainingPrize = totalPrizePool;
        comp.winnersSet = false;
        comp.exists = true;

        // Simpan daftar hadiah
        for (uint256 i = 0; i < _prizeTitles.length; i++) {
            competitionPrizes[competitionId].push(
                Prize({
                    title: _prizeTitles[i],
                    amount: _prizeAmounts[i],
                    certCID: _prizeCertCIDs[i]
                })
            );
        }

        emit CompetitionCreated(
            competitionId,
            msg.sender,
            _title,
            totalPrizePool,
            startTime,
            endTime
        );

        return competitionId;
    }

    /**
     * @dev Menentukan pemenang lomba
     * @notice Hadiah otomatis dikirim ke pemenang saat set winner
     * @param _competitionId ID lomba
     * @param _winnerAddresses Array alamat pemenang (sesuai urutan juara)
     */
    function setWinners(
        uint256 _competitionId,
        address[] calldata _winnerAddresses
    ) external onlyOrganizer competitionExists(_competitionId) nonReentrant {
        Competition storage comp = competitions[_competitionId];

        require(comp.organizer == msg.sender, "Not competition organizer");
        require(!comp.winnersSet, "Winners already set");
        require(
            _winnerAddresses.length == competitionPrizes[_competitionId].length,
            "Winner count must match prize count"
        );

        // Set winners & kirim hadiah
        for (uint256 i = 0; i < _winnerAddresses.length; i++) {
            address winnerAddr = _winnerAddresses[i];
            require(winnerAddr != address(0), "Invalid winner address");
            require(!isWinner[_competitionId][winnerAddr], "Duplicate winner");

            Prize storage prize = competitionPrizes[_competitionId][i];

            winners[_competitionId].push(winnerAddr);
            isWinner[_competitionId][winnerAddr] = true;

            // Kirim hadiah otomatis
            if (prize.amount > 0) {
                (bool success, ) = payable(winnerAddr).call{
                    value: prize.amount
                }("");
                require(success, "Prize transfer failed");
                comp.remainingPrize -= prize.amount;

                emit PrizeClaimed(_competitionId, winnerAddr, prize.amount);
            }

            emit WinnerSet(_competitionId, winnerAddr, prize.amount, i);
        }

        comp.winnersSet = true;
    }

    // ============ User Functions ============

    /**
     * @dev User claim sertifikat peserta
     */
    function claimParticipantCertificate(
        uint256 _competitionId
    ) external competitionExists(_competitionId) {
        Competition storage comp = competitions[_competitionId];
        require(
            !hasClaimedParticipantCert[_competitionId][msg.sender],
            "Already claimed participant cert"
        );
        require(
            bytes(comp.participantCertCID).length > 0,
            "Participant cert not available"
        );

        hasClaimedParticipantCert[_competitionId][msg.sender] = true;

        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, comp.participantCertCID);

        emit CertificateClaimed(
            _competitionId,
            msg.sender,
            tokenId,
            "participant"
        );
    }

    /**
     * @dev User (pemenang) claim sertifikat juara
     */
    function claimWinnerCertificate(
        uint256 _competitionId
    ) external competitionExists(_competitionId) {
        Competition storage comp = competitions[_competitionId];
        require(comp.winnersSet, "Winners not set yet");
        require(isWinner[_competitionId][msg.sender], "Not a winner");
        require(
            !hasClaimedWinnerCert[_competitionId][msg.sender],
            "Already claimed winner cert"
        );

        // Cari index pemenang untuk ambil certCID
        uint256 winnerIndex = _getWinnerIndex(_competitionId, msg.sender);
        Prize storage prize = competitionPrizes[_competitionId][winnerIndex];
        require(bytes(prize.certCID).length > 0, "Winner cert not available");

        hasClaimedWinnerCert[_competitionId][msg.sender] = true;

        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, prize.certCID);

        emit CertificateClaimed(_competitionId, msg.sender, tokenId, "winner");
    }

    // ============ View Functions ============

    function getCompetition(
        uint256 _competitionId
    ) external view returns (Competition memory) {
        require(competitions[_competitionId].exists, "Competition not found");
        return competitions[_competitionId];
    }

    function getCompetitionPrizes(
        uint256 _competitionId
    ) external view returns (Prize[] memory) {
        return competitionPrizes[_competitionId];
    }

    function getWinners(
        uint256 _competitionId
    ) external view returns (address[] memory) {
        return winners[_competitionId];
    }

    function isCompetitionActive(
        uint256 _competitionId
    ) external view returns (bool) {
        Competition storage comp = competitions[_competitionId];
        return
            comp.exists && block.timestamp < comp.endTime && !comp.winnersSet;
    }

    function getTotalCompetitions() external view returns (uint256) {
        return competitionCounter;
    }

    // ============ Internal Functions ============

    function _getWinnerIndex(
        uint256 _competitionId,
        address _winner
    ) internal view returns (uint256) {
        address[] storage w = winners[_competitionId];
        for (uint256 i = 0; i < w.length; i++) {
            if (w[i] == _winner) return i;
        }
        revert("Winner not found");
    }

    // ============ Overrides ============

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
