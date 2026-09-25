// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IPFSHelper} from "./helpers/IPFSHelper.sol";

contract CompetitionManager is ERC721, ERC721URIStorage, Ownable {
    // =============================================================
    //                      STRUCTS
    // =============================================================

    struct Competitions {
        uint256 id;
        string cid;
        string formation;
        address organization;
        uint256 prizeCertificateClaim;
        string certificateCID;
    }

    struct Winners {
        uint256 id;
        uint256 competitionId;
        address prizeToken;
        uint256 prizeAmount;
        string certificateCID;
    }

    struct ParticipantWinner {
        uint256 id;
        uint256 winnerId;
        address participant;
    }

    struct PriceCompetitionFee {
        uint256 id;
        uint256 treasuryFee;
        address tokenAddress;
        string cid;
    }

    struct ListingTokenPrize {
        uint256 id;
        address tokenAddress;
        bool isActive;
    }

    struct CertificateParticipant {
        uint256 id;
        uint256 competitionId;
        address participant;
    }

    struct CertificateParticipantWinner {
        uint256 id;
        uint256 competitionId;
        address participant;
    }

    struct TreasuryPrize {
        uint256 id;
        uint256 competitionId;
        address organization;
        uint256 totalPrize;
        address tokenAddress;
    }

    // =============================================================
    //                      CONSTANTS & STORAGE
    // =============================================================

    string public constant FORMATION_1_3_MEMBER = "1-3 member";
    string public constant FORMATION_1_5_MEMBER = "1-5 member";

    uint256 private competitionId;
    uint256 private winnerId;
    uint256 private participantWinnerId;

    mapping(uint256 => Competitions) public competitions;
    mapping(uint256 => Winners[]) public winners;
    mapping(uint256 => Winners) public winnerById;
    mapping(uint256 => ParticipantWinner[]) public participantWinner;
    mapping(uint256 => uint256) public competitionTotalPrize;

    // --- Price Competition Fee Storage ---
    uint256 private priceCompetitionFeeId;
    mapping(uint256 => PriceCompetitionFee) public priceCompetitionFees;

    // --- Listing Token Prize Storage ---
    uint256 private listingTokenPrizeId;
    mapping(address => ListingTokenPrize) public listingToken;

    // --- Signer Storage ---
    address public signerAddress;

    // --- Certificate Manager Storage ---
    uint256 private certificateParticipantId;
    uint256 private certificateParticipantWinnerId;

    mapping(uint256 => CertificateParticipant) public certificateParticipant;
    mapping(uint256 => CertificateParticipantWinner)
        public certificateParticipantWinner;

    mapping(address => mapping(uint256 => bool))
        public hasCertificateParticipant;
    mapping(address => mapping(uint256 => bool))
        public hasCertificateParticipantWinner;

    // --- Certificate Competition (ERC721) Storage ---
    uint256 private _nextTokenId;

    // --- Treasury Prize Storage ---
    uint256 private treasuryPrizeId;
    mapping(uint256 => TreasuryPrize) public treasuryPrize;
    mapping(uint256 => TreasuryPrize) public treasuryPrizeByCompetitionId;

    // =============================================================
    //                      EVENTS
    // =============================================================

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
        string certificateCID
    );

    event CompetitionFeePaid(
        uint256 indexed competitionId,
        address indexed payer,
        address indexed tokenAddress,
        uint256 amount
    );

    // --- Price Competition Fee Events ---
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

    // --- Listing Token Prize Events ---
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

    // --- Signer Events ---
    event SignerAddressUpdated(address indexed signerAddress);

    // --- Certificate Manager Events ---
    event CertificateParticipantAdded(
        uint256 indexed id,
        uint256 indexed competitionId,
        address indexed participant
    );

    event CertificateParticipantWinnerAdded(
        uint256 indexed id,
        uint256 indexed competitionId,
        address indexed participant,
        uint256 winnerId
    );

    // --- Certificate Competition Events ---
    event CertificateParticipantMinted(
        uint256 indexed tokenId,
        address indexed participant,
        uint256 indexed competitionId,
        string uri
    );

    event CertificateParticipantWinnerMinted(
        uint256 indexed tokenId,
        address indexed participant,
        uint256 indexed competitionId,
        uint256 winnerId,
        string uri
    );

    // --- Treasury Platform Events ---
    event TreasuryAdded(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event NativeReceived(address indexed sender, uint256 amount);

    event OwnerUpdated(address indexed addressOwner);

    // --- Treasury Prize Events ---
    event PrizeDeposited(
        uint256 indexed treasuryPrizeId,
        uint256 indexed competitionId,
        address indexed tokenAddress,
        address sender,
        uint256 amount
    );

    event PrizeDistributed(
        uint256 indexed treasuryPrizeId,
        uint256 indexed competitionId,
        address indexed tokenAddress,
        address recipient,
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
                competitions[_competitionId].prizeCertificateClaim,
            "Competition is not ended"
        );

        _;
    }

    constructor(
        address initialOwner,
        address _signerAddress
    ) ERC721("Certificate Competition", "CC") Ownable(initialOwner) {
        signerAddress = _signerAddress;
    }

    // =============================================================
    //                   SIGNER MANAGER FUNCTIONS
    // =============================================================

    function updateSignerAddress(address _signerAddress) external onlyOwner {
        signerAddress = _signerAddress;
        emit SignerAddressUpdated(_signerAddress);
    }

    // =============================================================
    //               LISTING TOKEN PRIZE FUNCTIONS
    // =============================================================

    function addListingTokenPrize(address _tokenAddress) external onlyOwner {
        require(listingToken[_tokenAddress].id == 0, "Token already listed");

        listingTokenPrizeId++;

        listingToken[_tokenAddress] = ListingTokenPrize({
            id: listingTokenPrizeId,
            tokenAddress: _tokenAddress,
            isActive: true
        });

        emit ListingTokenPrizeAdded(listingTokenPrizeId, _tokenAddress, true);
    }

    function deactivateListingTokenPrize(
        address _tokenAddress
    ) external onlyOwner {
        require(listingToken[_tokenAddress].id != 0, "Token is not listed");

        require(
            listingToken[_tokenAddress].isActive,
            "Token already deactivated"
        );

        listingToken[_tokenAddress].isActive = false;

        emit ListingTokenPrizeDeactivated(
            listingToken[_tokenAddress].id,
            _tokenAddress,
            listingToken[_tokenAddress].isActive
        );
    }

    function isTokenListed(address _tokenAddress) external view returns (bool) {
        return listingToken[_tokenAddress].id != 0;
    }

    // =============================================================
    //            PRICE COMPETITION MANAGER FUNCTIONS
    // =============================================================

    function setPriceCompetitionFee(
        uint256 _treasuryFee,
        address _tokenAddress,
        string calldata _cid
    ) external onlyOwner {
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
        require(
            priceCompetitionFees[_priceCompetitionFeeId].id != 0,
            "Price competition fee not found"
        );

        priceCompetitionFees[_priceCompetitionFeeId].treasuryFee = _treasuryFee;

        priceCompetitionFees[_priceCompetitionFeeId]
            .tokenAddress = _tokenAddress;

        priceCompetitionFees[_priceCompetitionFeeId].cid = _cid;

        emit PriceCompetitionFeeUpdated(
            _priceCompetitionFeeId,
            _treasuryFee,
            _tokenAddress,
            _cid
        );
    }

    function getPriceCompetitionFee(
        uint256 _priceCompetitionFeeId
    ) external view returns (PriceCompetitionFee memory) {
        return priceCompetitionFees[_priceCompetitionFeeId];
    }

    // =============================================================
    //                 TREASURY PLATFORM FUNCTIONS
    // =============================================================

    function updateOwner(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
        emit OwnerUpdated(newOwner);
    }

    function addTreasuryFrom(
        address sender,
        address _tokenAddress,
        uint256 amount
    ) public payable {
        address actualSender = sender == address(0) ? msg.sender : sender;

        require(amount > 0, "Amount must be greater than 0");

        address recipient = owner();

        if (_tokenAddress == address(0)) {
            require(msg.value == amount, "Incorrect native amount");

            (bool success, ) = payable(recipient).call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            require(msg.value == 0, "Do not send native token");

            bool success = IERC20(_tokenAddress).transferFrom(
                actualSender,
                recipient,
                amount
            );

            require(success, "Transfer failed");
        }

        emit TreasuryAdded(_tokenAddress, actualSender, amount);
    }

    // =============================================================
    //                  TREASURY PRIZE FUNCTIONS
    // =============================================================

    function addTreasury(
        TreasuryPrize calldata _treasuryPrize,
        address _from
    ) public payable {
        require(_treasuryPrize.totalPrize > 0, "Amount must be greater than 0");

        address sender = _from == address(0) ? msg.sender : _from;

        if (_treasuryPrize.tokenAddress == address(0)) {
            require(
                msg.value == _treasuryPrize.totalPrize,
                "Incorrect native amount"
            );
        } else {
            require(msg.value == 0, "Do not send native token");
            bool success = IERC20(_treasuryPrize.tokenAddress).transferFrom(
                sender,
                address(this),
                _treasuryPrize.totalPrize
            );
            require(success, "Transfer failed");
        }

        treasuryPrizeId++;
        TreasuryPrize memory newEntry = TreasuryPrize({
            id: treasuryPrizeId,
            competitionId: _treasuryPrize.competitionId,
            organization: sender,
            totalPrize: _treasuryPrize.totalPrize,
            tokenAddress: _treasuryPrize.tokenAddress
        });

        treasuryPrize[treasuryPrizeId] = newEntry;
        treasuryPrizeByCompetitionId[_treasuryPrize.competitionId] = newEntry;

        emit PrizeDeposited(
            treasuryPrizeId,
            _treasuryPrize.competitionId,
            _treasuryPrize.tokenAddress,
            sender,
            _treasuryPrize.totalPrize
        );
    }

    function payout(
        uint256 _competitionId,
        address payable _to,
        uint256 _amount,
        address _tokenAddress,
        address _from
    ) public {
        address caller = _from == address(0) ? msg.sender : _from;

        TreasuryPrize storage compPrize = treasuryPrizeByCompetitionId[
            _competitionId
        ];
        require(
            compPrize.organization != address(0),
            "Treasury does not exist"
        );
        require(
            caller == compPrize.organization,
            "Only organization can payout"
        );
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be greater than 0");
        require(compPrize.totalPrize >= _amount, "Insufficient prize balance");
        require(
            compPrize.tokenAddress == _tokenAddress,
            "Token address mismatch"
        );

        compPrize.totalPrize -= _amount;

        uint256 tId = compPrize.id;
        if (tId != 0) {
            treasuryPrize[tId].totalPrize -= _amount;
        }

        if (_tokenAddress == address(0)) {
            (bool success, ) = _to.call{value: _amount}("");
            require(success, "Native transfer failed");
        } else {
            bool success = IERC20(_tokenAddress).transfer(_to, _amount);
            require(success, "Transfer failed");
        }

        emit PrizeDistributed(tId, _competitionId, _tokenAddress, _to, _amount);
    }

    function isValidFormation(
        string memory _formation
    ) public pure returns (bool) {
        return
            keccak256(bytes(_formation)) ==
            keccak256(bytes(FORMATION_1_3_MEMBER)) ||
            keccak256(bytes(_formation)) ==
            keccak256(bytes(FORMATION_1_5_MEMBER));
    }

    function createCompetition(
        Competitions calldata _competition,
        Winners[] calldata _winners,
        uint256 _priceCompetitionFeeId
    ) external payable {
        require(
            _competition.prizeCertificateClaim > block.timestamp,
            "Invalid end time"
        );

        require(isValidFormation(_competition.formation), "Invalid formation");

        require(_winners.length > 0, "Must have at least one winner");

        address sender = _competition.organization == address(0)
            ? msg.sender
            : _competition.organization;

        competitionId++;

        competitions[competitionId] = _competition;

        competitions[competitionId].id = competitionId;
        competitions[competitionId].organization = sender;

        PriceCompetitionFee memory platformFee = priceCompetitionFees[
            _priceCompetitionFeeId
        ];

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

            ListingTokenPrize memory listed = listingToken[_winners[i].prizeToken];

            require(
                listed.tokenAddress == _winners[i].prizeToken,
                "Prize token is not listed"
            );

            require(listed.isActive, "Prize token is not active");

            totalPrizeAmount += _winners[i].prizeAmount;

            winnerId++;

            Winners memory newWinner = Winners({
                id: winnerId,
                competitionId: competitionId,
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
                this.addTreasuryFrom{value: fee}(
                    sender,
                    address(0),
                    fee
                );
            } else {
                addTreasuryFrom(sender, feeToken, fee);
            }

            emit CompetitionFeePaid(competitionId, sender, feeToken, fee);
        }

        if (totalPrizeAmount > 0) {
            uint256 nativePrizeValue = firstPrizeToken == address(0)
                ? totalPrizeAmount
                : 0;

            this.addTreasury{value: nativePrizeValue}(
                TreasuryPrize({
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

        payout(
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
            winner_participant.certificateCID
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
            competitions[_competitionId].prizeCertificateClaim;
    }

    // =============================================================
    //                 CERTIFICATE MANAGER FUNCTIONS
    // =============================================================

    function addCertificateParticipant(
        address _participant,
        uint256 _competitionId,
        bytes memory signature
    ) public {
        Competitions memory comp = competitions[_competitionId];

        require(comp.id != 0, "Competition does not exist");

        require(
            !hasCertificateParticipant[_participant][_competitionId],
            "Certificate participant already exists"
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                msg.sender,
                _participant,
                _participant,
                _competitionId,
                IPFSHelper.toIPFSURI(comp.certificateCID)
            )
        );

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );

        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            signature
        );

        require(
            recoveredSigner == signerAddress,
            "Invalid signature"
        );

        certificateParticipantId++;

        certificateParticipant[
            certificateParticipantId
        ] = CertificateParticipant({
            id: certificateParticipantId,
            competitionId: _competitionId,
            participant: _participant
        });

        hasCertificateParticipant[_participant][_competitionId] = true;

        emit CertificateParticipantAdded(
            certificateParticipantId,
            _competitionId,
            _participant
        );
    }

    function addCertificateParticipantWinner(
        address _participant,
        uint256 _competitionId,
        uint256 _winnerId,
        bytes memory signature
    ) public {
        Competitions memory comp = competitions[_competitionId];

        require(comp.id != 0, "Competition does not exist");

        require(
            !hasCertificateParticipantWinner[_participant][_winnerId],
            "Certificate participant winner already exists"
        );

        Winners memory winner = winnerById[_winnerId];

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                msg.sender,
                _participant,
                _participant,
                _winnerId,
                IPFSHelper.toIPFSURI(winner.certificateCID)
            )
        );

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );

        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            signature
        );

        require(
            recoveredSigner == signerAddress,
            "Invalid signature"
        );

        certificateParticipantWinnerId++;

        certificateParticipantWinner[
            certificateParticipantWinnerId
        ] = CertificateParticipantWinner({
            id: certificateParticipantWinnerId,
            competitionId: _competitionId,
            participant: _participant
        });

        hasCertificateParticipantWinner[_participant][_winnerId] = true;

        emit CertificateParticipantWinnerAdded(
            certificateParticipantWinnerId,
            _competitionId,
            _participant,
            _winnerId
        );
    }

    // =============================================================
    //             CERTIFICATE COMPETITION (NFT) FUNCTIONS
    // =============================================================

    function safeMintCertificateParticipant(
        uint256 _competitionId,
        bytes memory signature
    ) public onlyCompetitionEnd(_competitionId) returns (uint256) {
        require(
            !hasCertificateParticipant[msg.sender][_competitionId],
            "Certificate participant already claimed"
        );

        Competitions memory competition = competitions[_competitionId];

        string memory uri = IPFSHelper.toIPFSURI(competition.certificateCID);

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                msg.sender,
                _competitionId,
                uri
            )
        );

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );

        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            signature
        );

        require(
            recoveredSigner == signerAddress,
            "Invalid signature"
        );

        uint256 tokenId = _nextTokenId++;

        _safeMint(msg.sender, tokenId);

        _setTokenURI(tokenId, uri);

        addCertificateParticipant(
            msg.sender,
            _competitionId,
            signature
        );

        emit CertificateParticipantMinted(
            tokenId,
            msg.sender,
            _competitionId,
            uri
        );

        return tokenId;
    }

    function safeMintCertificateParticipantWinner(
        uint256 _winnerId,
        bytes memory signature
    ) public returns (uint256) {
        Winners memory winner = winnerById[_winnerId];

        Competitions memory competition = competitions[winner.competitionId];

        require(competition.id != 0, "Competition does not exist");

        require(
            block.timestamp >= competition.prizeCertificateClaim,
            "Competition is not ended"
        );

        require(
            !hasCertificateParticipantWinner[msg.sender][_winnerId],
            "Certificate participant winner already claimed"
        );

        string memory uri = IPFSHelper.toIPFSURI(winner.certificateCID);

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                address(this),
                msg.sender,
                msg.sender,
                _winnerId,
                uri
            )
        );

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );

        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            signature
        );

        require(
            recoveredSigner == signerAddress,
            "Invalid signature"
        );

        uint256 tokenId = _nextTokenId++;

        _safeMint(msg.sender, tokenId);

        _setTokenURI(tokenId, uri);

        addCertificateParticipantWinner(
            msg.sender,
            winner.competitionId,
            _winnerId,
            signature
        );

        emit CertificateParticipantWinnerMinted(
            tokenId,
            msg.sender,
            winner.competitionId,
            _winnerId,
            uri
        );

        return tokenId;
    }

    // =============================================================
    //                     ERC721 OVERRIDES
    // =============================================================

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721) returns (address) {
        address previousOwner = super._update(to, tokenId, auth);

        require(
            previousOwner == address(0) || to == address(0),
            "Certificate NFTs are non-transferable"
        );

        return previousOwner;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // =============================================================
    //                       RECEIVE FALLBACK
    // =============================================================

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
}
