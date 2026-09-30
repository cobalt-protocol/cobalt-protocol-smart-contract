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
    //                      CUSTOM ERRORS
    // =============================================================

    error CompetitionDoesNotExist();
    error NotOrganization();
    error CompetitionNotEnded();
    error TokenAlreadyListed();
    error TokenNotListed();
    error TokenAlreadyDeactivated();
    error PriceFeeNotFound();
    error AmountZero();
    error IncorrectNativeAmount();
    error DoNotSendNative();
    error TransferFailed();
    error TreasuryDoesNotExist();
    error InvalidRecipient();
    error InsufficientPrizeBalance();
    error InvalidFormation();
    error MustHaveWinner();
    error InvalidEndTime();
    error FeeOptionNotFound();
    error PrizeAmountZero();
    error PrizeTokenMismatch();
    error PrizeTokenNotListed();
    error PrizeTokenNotActive();
    error WinnerDoesNotExist();
    error WinnerMismatch();
    error InsufficientCompetitionPrize();
    error CertificateAlreadyClaimed();
    error InvalidSignature();
    error CertificateNonTransferable();

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

    mapping(uint256 => Competitions) public competitions;
    mapping(uint256 => Winners[]) public winners;
    mapping(uint256 => Winners) public winnerById;
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
    mapping(address => mapping(uint256 => bool))
        public hasCertificateParticipant;
    mapping(address => mapping(uint256 => bool))
        public hasCertificateParticipantWinner;

    // --- Certificate Competition (ERC721) Storage ---
    uint256 private _nextTokenId;

    // --- Treasury Prize Storage ---
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
        if (competitions[_competition_id].id == 0) revert CompetitionDoesNotExist();
        if (competitions[_competition_id].organization != _address_organization) revert NotOrganization();

        _;
    }

    modifier onlyCompetitionEnd(uint256 _competitionId) {
        if (competitions[_competitionId].id == 0) revert CompetitionDoesNotExist();
        if (block.timestamp < competitions[_competitionId].prizeCertificateClaim) revert CompetitionNotEnded();

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
        if (listingToken[_tokenAddress].id != 0) revert TokenAlreadyListed();

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
        if (listingToken[_tokenAddress].id == 0) revert TokenNotListed();

        if (!listingToken[_tokenAddress].isActive) revert TokenAlreadyDeactivated();

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
        if (priceCompetitionFees[_priceCompetitionFeeId].id == 0) revert PriceFeeNotFound();

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

        if (amount == 0) revert AmountZero();

        address recipient = owner();

        if (_tokenAddress == address(0)) {
            if (msg.value != amount) revert IncorrectNativeAmount();

            (bool success, ) = payable(recipient).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            if (msg.value != 0) revert DoNotSendNative();

            bool success = IERC20(_tokenAddress).transferFrom(
                actualSender,
                recipient,
                amount
            );

            if (!success) revert TransferFailed();
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
        if (_treasuryPrize.totalPrize == 0) revert AmountZero();

        address sender = _from == address(0) ? msg.sender : _from;

        if (_treasuryPrize.tokenAddress == address(0)) {
            if (msg.value != _treasuryPrize.totalPrize) revert IncorrectNativeAmount();
        } else {
            if (msg.value != 0) revert DoNotSendNative();
            bool success = IERC20(_treasuryPrize.tokenAddress).transferFrom(
                sender,
                address(this),
                _treasuryPrize.totalPrize
            );
            if (!success) revert TransferFailed();
        }

        TreasuryPrize memory newEntry = TreasuryPrize({
            id: _treasuryPrize.competitionId,
            competitionId: _treasuryPrize.competitionId,
            organization: sender,
            totalPrize: _treasuryPrize.totalPrize,
            tokenAddress: _treasuryPrize.tokenAddress
        });

        treasuryPrizeByCompetitionId[_treasuryPrize.competitionId] = newEntry;

        emit PrizeDeposited(
            _treasuryPrize.competitionId,
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
        if (compPrize.organization == address(0)) revert TreasuryDoesNotExist();
        if (caller != compPrize.organization) revert NotOrganization();
        if (_to == address(0)) revert InvalidRecipient();
        if (_amount == 0) revert AmountZero();
        if (compPrize.totalPrize < _amount) revert InsufficientPrizeBalance();
        if (compPrize.tokenAddress != _tokenAddress) revert PrizeTokenMismatch();

        compPrize.totalPrize -= _amount;

        if (_tokenAddress == address(0)) {
            (bool success, ) = _to.call{value: _amount}("");
            if (!success) revert TransferFailed();
        } else {
            bool success = IERC20(_tokenAddress).transfer(_to, _amount);
            if (!success) revert TransferFailed();
        }

        emit PrizeDistributed(_competitionId, _competitionId, _tokenAddress, _to, _amount);
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
        if (_competition.prizeCertificateClaim <= block.timestamp) revert InvalidEndTime();
        if (!isValidFormation(_competition.formation)) revert InvalidFormation();
        if (_winners.length == 0) revert MustHaveWinner();

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

        if (platformFee.id == 0) revert FeeOptionNotFound();

        uint256 fee = platformFee.treasuryFee;
        address feeToken = platformFee.tokenAddress;

        uint256 totalPrizeAmount = 0;
        address firstPrizeToken = _winners[0].prizeToken;

        for (uint256 i = 0; i < _winners.length; i++) {
            if (_winners[i].prizeAmount == 0) revert PrizeAmountZero();
            if (_winners[i].prizeToken != firstPrizeToken) revert PrizeTokenMismatch();

            ListingTokenPrize memory listed = listingToken[_winners[i].prizeToken];

            if (listed.tokenAddress != _winners[i].prizeToken) revert PrizeTokenNotListed();
            if (!listed.isActive) revert PrizeTokenNotActive();

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

        if (msg.value != requiredNative) revert IncorrectNativeAmount();

        if (fee > 0) {
            address recipient = owner();
            if (feeToken == address(0)) {
                (bool success, ) = payable(recipient).call{value: fee}("");
                if (!success) revert TransferFailed();
                emit TreasuryAdded(address(0), sender, fee);
            } else {
                bool success = IERC20(feeToken).transferFrom(
                    sender,
                    recipient,
                    fee
                );
                if (!success) revert TransferFailed();
                emit TreasuryAdded(feeToken, sender, fee);
            }

            emit CompetitionFeePaid(competitionId, sender, feeToken, fee);
        }

        if (totalPrizeAmount > 0) {
            if (firstPrizeToken != address(0)) {
                bool success = IERC20(firstPrizeToken).transferFrom(
                    sender,
                    address(this),
                    totalPrizeAmount
                );
                if (!success) revert TransferFailed();
            }

            TreasuryPrize memory newEntry = TreasuryPrize({
                id: competitionId,
                competitionId: competitionId,
                organization: sender,
                totalPrize: totalPrizeAmount,
                tokenAddress: firstPrizeToken
            });

            treasuryPrizeByCompetitionId[competitionId] = newEntry;

            emit PrizeDeposited(
                competitionId,
                competitionId,
                firstPrizeToken,
                sender,
                totalPrizeAmount
            );
        }
    }

    function setWinner(
        uint256 _winnerId,
        address _participant,
        uint256 _competition_id
    ) external onlyOrganization(msg.sender, _competition_id) {
        if (winnerById[_winnerId].id == 0) revert WinnerDoesNotExist();
        if (winnerById[_winnerId].competitionId != _competition_id) revert WinnerMismatch();

        Winners memory winner_participant = winnerById[_winnerId];

        if (competitionTotalPrize[_competition_id] < winner_participant.prizeAmount) revert InsufficientCompetitionPrize();

        competitionTotalPrize[_competition_id] -= winner_participant.prizeAmount;

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
        if (winnerById[_winnerId].id == 0) revert WinnerDoesNotExist();

        return winnerById[_winnerId];
    }

    function isCompetitionEnded(
        uint256 _competitionId
    ) external view returns (bool) {
        return
            block.timestamp >=
            competitions[_competitionId].prizeCertificateClaim;
    }

    // =============================================================
    //             CERTIFICATE COMPETITION (NFT) FUNCTIONS
    // =============================================================

    function safeMintCertificateParticipant(
        uint256 _competitionId,
        bytes memory signature
    ) public onlyCompetitionEnd(_competitionId) returns (uint256) {
        if (hasCertificateParticipant[msg.sender][_competitionId]) revert CertificateAlreadyClaimed();

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

        if (recoveredSigner != signerAddress) revert InvalidSignature();

        hasCertificateParticipant[msg.sender][_competitionId] = true;

        uint256 tokenId = _nextTokenId++;

        _safeMint(msg.sender, tokenId);

        _setTokenURI(tokenId, uri);

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

        if (competition.id == 0) revert CompetitionDoesNotExist();
        if (block.timestamp < competition.prizeCertificateClaim) revert CompetitionNotEnded();
        if (hasCertificateParticipantWinner[msg.sender][_winnerId]) revert CertificateAlreadyClaimed();

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

        if (recoveredSigner != signerAddress) revert InvalidSignature();

        hasCertificateParticipantWinner[msg.sender][_winnerId] = true;

        uint256 tokenId = _nextTokenId++;

        _safeMint(msg.sender, tokenId);

        _setTokenURI(tokenId, uri);

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

        if (previousOwner != address(0) && to != address(0)) revert CertificateNonTransferable();

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
