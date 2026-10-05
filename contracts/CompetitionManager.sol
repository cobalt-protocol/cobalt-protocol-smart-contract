// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import {IPFSHelper} from "./helpers/IPFSHelper.sol";
import {CertificateHelper} from "./helpers/CertificateHelper.sol";
import {FormationHelper} from "./helpers/FormationHelper.sol";
import {CompetitionHelper} from "./helpers/CompetitionHelper.sol";
import {CompetitionModifiers} from "./helpers/modifier/CompetitionModifiers.sol";

contract CompetitionManager is ERC721, ERC721URIStorage, Ownable, CompetitionModifiers {
    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error TokenAlreadyListed();
    error TokenAlreadyDeactivated();
    error PriceFeeNotFound();
    error AmountZero();
    error IncorrectNativeAmount();
    error IncorrectFeeAmount();
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
    error WinnerDoesNotExist();
    error WinnerMismatch();
    error InsufficientCompetitionPrize();
    error CertificateAlreadyClaimed();
    error CertificateNonTransferable();
    error InvalidTeamId();
    error NativeFromMismatch();

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
        uint256 teamId;
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
    //                      STORAGE
    // =============================================================

    uint256 private competitionId;
    uint256 private winnerId;
    uint256 private priceCompetitionFeeId;
    uint256 private listingTokenId;
    uint256 private _nextTokenId;

    address public signerAddress;

    mapping(uint256 => Competitions) public competitions;
    mapping(uint256 => Winners[]) public winners;
    mapping(uint256 => Winners) public winnerById;
    mapping(uint256 => uint256) public competitionTotalPrize;
    mapping(uint256 => PriceCompetitionFee) public priceCompetitionFees;
    mapping(address => CompetitionHelper.ListingToken) public listingToken;
    mapping(uint256 => TreasuryPrize) public treasuryPrizeByCompetitionId;
    mapping(uint256 => mapping(address => uint256)) public totalPaid;

    // key = keccak256(competitionId, teamId, wallet)
    mapping(bytes32 => bool) public claimedParticipantCertificate;
    mapping(bytes32 => bool) public claimedWinnerCertificate;

    // =============================================================
    //                      EVENTS
    // =============================================================

    event CompetitionCreated(
        uint256 indexed id,
        address indexed organization,
        string cid,
        string formation,
        uint256 prizeCertificateClaim,
        string certificateCID,
        uint256 priceCompetitionFeeId
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
        string certificateCID,
        uint256 teamId
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

    event SignerAddressUpdated(address indexed signerAddress);

    event CertificateParticipantMinted(
        uint256 indexed tokenId,
        address indexed participant,
        uint256 indexed competitionId,
        uint256 teamId,
        bytes signature,
        string uri
    );

    event CertificateParticipantWinnerMinted(
        uint256 indexed tokenId,
        address indexed participant,
        uint256 indexed competitionId,
        uint256 winnerId,
        uint256 teamId,
        bytes signature,
        string uri
    );

    event TreasuryAdded(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event NativeReceived(address indexed sender, uint256 amount);

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

    event TeamPaymentCreated(
        uint256 indexed competitionId,
        string cid,
        address indexed token,
        address indexed from,
        address to,
        uint256 amount
    );

    // =============================================================
    //              CompetitionModifiers overrides
    // =============================================================

    function _competitionExists(uint256 competitionId) internal view override returns (bool) {
        return competitions[competitionId].id != 0;
    }

    function _competitionOrganization(uint256 competitionId) internal view override returns (address) {
        return competitions[competitionId].organization;
    }

    function _competitionPrizeCertificateClaim(uint256 competitionId) internal view override returns (uint256) {
        return competitions[competitionId].prizeCertificateClaim;
    }

    constructor(
        address initialOwner,
        address _signerAddress
    ) ERC721("Certificate Competition", "CC") Ownable(initialOwner) {
        signerAddress = _signerAddress;
    }

    // =============================================================
    //                   ADMIN
    // =============================================================

    function updateSignerAddress(address _signerAddress) external onlyOwner {
        signerAddress = _signerAddress;
        emit SignerAddressUpdated(_signerAddress);
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

    // =============================================================
    //                  TEAM PAYMENT
    // =============================================================

    function paymentCreateTeam(
        uint256 _competitionId,
        string calldata cid,
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) external payable {
        Competitions storage comp = competitions[_competitionId];
        if (comp.id == 0) revert CompetitionDoesNotExist();
        if (_amount != comp.payment.fee) revert IncorrectFeeAmount();
        if (_to == address(0)) revert InvalidRecipient();
        if (_amount == 0) revert AmountZero();

        if (_token == address(0)) {
            if (_from != msg.sender) revert NativeFromMismatch();
            if (msg.value != _amount) revert IncorrectNativeAmount();
            (bool ok, ) = payable(_to).call{value: _amount}("");
            if (!ok) revert TransferFailed();
        } else {
            if (msg.value != 0) revert IncorrectNativeAmount();
            if (!IERC20(_token).transferFrom(_from, _to, _amount))
                revert TransferFailed();
        }

        totalPaid[_competitionId][_token] += _amount;

        emit TeamPaymentCreated(
            _competitionId,
            cid,
            _token,
            _from,
            _to,
            _amount
        );
    }

    // =============================================================
    //                  CREATE COMPETITION
    // =============================================================

    function createCompetition(
        Competitions calldata _competition,
        CompetitionPayment calldata _payment,
        Winners[] calldata _winners,
        uint256 _priceCompetitionFeeId
    ) external payable {
        if (_competition.prizeCertificateClaim <= block.timestamp)
            revert InvalidEndTime();
        if (!FormationHelper.isValidFormation(_competition.formation))
            revert InvalidFormation();
        if (_winners.length == 0) revert MustHaveWinner();

        CompetitionHelper.requireTokenActive(
            listingToken[_payment.tokenAddress]
        );

        address sender = _competition.organization == address(0)
            ? msg.sender
            : _competition.organization;

        competitionId++;
        uint256 newId = competitionId;

        competitions[newId] = _competition;
        competitions[newId].id = newId;
        competitions[newId].organization = sender;
        competitions[newId].payment = _payment;

        emit CompetitionPaymentConfigured(
            newId,
            _payment.tokenAddress,
            _payment.fee
        );

        PriceCompetitionFee memory platformFee = priceCompetitionFees[
            _priceCompetitionFeeId
        ];
        if (platformFee.id == 0) revert FeeOptionNotFound();

        uint256 platformTreasuryFee = platformFee.treasuryFee;
        address platformFeeToken = platformFee.tokenAddress;

        uint256 totalPrizeAmount;
        address firstPrizeToken = _winners[0].prizeToken;

        for (uint256 i; i < _winners.length; ++i) {
            if (_winners[i].prizeAmount == 0) revert PrizeAmountZero();
            if (_winners[i].prizeToken != firstPrizeToken)
                revert PrizeTokenMismatch();
            if (_winners[i].teamId == 0) revert InvalidTeamId();

            CompetitionHelper.requireTokenActive(
                listingToken[_winners[i].prizeToken]
            );

            totalPrizeAmount += _winners[i].prizeAmount;
            winnerId++;

            Winners memory w = Winners({
                id: winnerId,
                competitionId: newId,
                prizeToken: _winners[i].prizeToken,
                prizeAmount: _winners[i].prizeAmount,
                certificateCID: _winners[i].certificateCID,
                teamId: _winners[i].teamId
            });

            winners[newId].push(w);
            winnerById[winnerId] = w;

            emit CompetitionWinnerConfigured(
                newId,
                winnerId,
                w.prizeToken,
                w.prizeAmount,
                w.certificateCID,
                w.teamId
            );
        }

        competitionTotalPrize[newId] = totalPrizeAmount;

        emit CompetitionCreated(
            newId,
            sender,
            competitions[newId].cid,
            competitions[newId].formation,
            competitions[newId].prizeCertificateClaim,
            competitions[newId].certificateCID,
            _priceCompetitionFeeId
        );

        // Native required = platform fee (if ETH) + prize (if ETH)
        uint256 requiredNative;
        if (platformTreasuryFee > 0 && platformFeeToken == address(0)) {
            requiredNative += platformTreasuryFee;
        }
        if (firstPrizeToken == address(0)) {
            requiredNative += totalPrizeAmount;
        }
        if (msg.value != requiredNative) revert IncorrectNativeAmount();

        // Platform fee
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
            emit TreasuryAdded(platformFeeToken, sender, platformTreasuryFee);
            emit CompetitionFeePaid(
                newId,
                sender,
                platformFeeToken,
                platformTreasuryFee
            );
        }

        // Prize escrow
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

    // =============================================================
    //                  SET WINNER / PAYOUT
    // =============================================================

    function setWinner(
        uint256 _winnerId,
        address _participant,
        uint256 _competitionId
    ) external onlyOrganization(_competitionId) {
        Winners memory w = winnerById[_winnerId];
        if (w.id == 0) revert WinnerDoesNotExist();
        if (w.competitionId != _competitionId) revert WinnerMismatch();
        if (competitionTotalPrize[_competitionId] < w.prizeAmount)
            revert InsufficientCompetitionPrize();

        competitionTotalPrize[_competitionId] -= w.prizeAmount;
        _payout(
            _competitionId,
            payable(_participant),
            w.prizeAmount,
            w.prizeToken
        );

        emit WinnerSet(
            _winnerId,
            _participant,
            _competitionId,
            w.certificateCID
        );
    }

    function _payout(
        uint256 _competitionId,
        address payable _to,
        uint256 _amount,
        address _tokenAddress
    ) internal {
        TreasuryPrize storage compPrize = treasuryPrizeByCompetitionId[
            _competitionId
        ];
        if (compPrize.organization == address(0)) revert TreasuryDoesNotExist();
        // caller already checked by onlyOrganization
        if (_to == address(0)) revert InvalidRecipient();
        if (_amount == 0) revert AmountZero();
        if (compPrize.totalPrize < _amount) revert InsufficientPrizeBalance();
        if (compPrize.tokenAddress != _tokenAddress)
            revert PrizeTokenMismatch();

        compPrize.totalPrize -= _amount;

        if (_tokenAddress == address(0)) {
            (bool ok, ) = _to.call{value: _amount}("");
            if (!ok) revert TransferFailed();
        } else {
            if (!IERC20(_tokenAddress).transfer(_to, _amount))
                revert TransferFailed();
        }

        emit PrizeDistributed(
            _competitionId,
            _competitionId,
            _tokenAddress,
            _to,
            _amount
        );
    }

    // =============================================================
    //                  READ / VIEW GETTERS
    // =============================================================

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

    // =============================================================
    //                  CERTIFICATES (NFT)
    // =============================================================

    function safeMintCertificateParticipant(
        uint256 _competitionId,
        uint256 _teamId,
        bytes calldata _signature,
        string calldata _cid
    ) external onlyCompetitionEnd(_competitionId) returns (uint256) {
        if (_teamId == 0) revert InvalidTeamId();

        bytes32 certId = CertificateHelper.certId(
            _competitionId,
            _teamId,
            msg.sender,
            _cid
        );
        if (claimedParticipantCertificate[certId])
            revert CertificateAlreadyClaimed();

        string memory uri = IPFSHelper.toIPFSURI(_cid);

        CompetitionHelper.verifySig(
            keccak256(
                abi.encodePacked(
                    address(this),
                    msg.sender,
                    _competitionId,
                    _teamId,
                    _cid
                )
            ),
            _signature,
            signerAddress
        );

        claimedParticipantCertificate[certId] = true;

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, uri);

        emit CertificateParticipantMinted(
            tokenId,
            msg.sender,
            _competitionId,
            _teamId,
            _signature,
            uri
        );
        return tokenId;
    }

    function safeMintCertificateParticipantWinner(
        uint256 _winnerId,
        bytes calldata signature,
        string calldata _cid
    ) external returns (uint256) {
        Winners memory w = winnerById[_winnerId];
        Competitions storage comp = competitions[w.competitionId];

        if (comp.id == 0) revert CompetitionDoesNotExist();
        if (block.timestamp < comp.prizeCertificateClaim)
            revert CompetitionNotEnded();

        bytes32 certId = CertificateHelper.certId(
            w.competitionId,
            w.teamId,
            msg.sender,
            _cid
        );
        if (claimedWinnerCertificate[certId])
            revert CertificateAlreadyClaimed();

        string memory uri = IPFSHelper.toIPFSURI(_cid);

        CompetitionHelper.verifySig(
            keccak256(
                abi.encodePacked(address(this), msg.sender, _winnerId, uri)
            ),
            signature,
            signerAddress
        );

        claimedWinnerCertificate[certId] = true;

        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, uri);

        emit CertificateParticipantWinnerMinted(
            tokenId,
            msg.sender,
            w.competitionId,
            _winnerId,
            w.teamId,
            signature,
            uri
        );
        return tokenId;
    }

    // =============================================================
    //                  ERC721 OVERRIDES
    // =============================================================

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721) returns (address) {
        address previousOwner = super._update(to, tokenId, auth);
        if (previousOwner != address(0) && to != address(0))
            revert CertificateNonTransferable();
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

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
}
