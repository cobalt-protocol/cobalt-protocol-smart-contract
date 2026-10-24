// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import {ManagerStorage} from "./ManagerStorage.sol";
import {CompetitionHelper} from "../helpers/CompetitionHelper.sol";
import {CertificateHelper} from "../helpers/CertificateHelper.sol";
import {IPFSHelper} from "../helpers/IPFSHelper.sol";

/// @title CertificateModule
/// @notice Sertifikat NFT (ERC721, non-transferable) untuk peserta dan pemenang.
abstract contract CertificateModule is
    ERC721,
    ERC721URIStorage,
    ManagerStorage
{
    error CertificateAlreadyClaimed();
    error CertificateNonTransferable();

    uint256 private _nextTokenId;

    // claimedParticipantCertificate key = keccak256(competitionId, teamId, wallet, cid)
    // claimedWinnerCertificate key = keccak256(competitionId, winnerId, teamId, wallet, cid)
    mapping(bytes32 => bool) internal claimedParticipantCertificate;
    mapping(bytes32 => bool) internal claimedWinnerCertificate;

    event CertificateParticipantMinted(
        uint256 indexed tokenId,
        address indexed participant,
        uint256 indexed competitionId,
        string teamId,
        bytes signature,
        string uri
    );

    event CertificateParticipantWinnerMinted(
        uint256 indexed tokenId,
        address indexed participant,
        uint256 indexed competitionId,
        uint256 winnerId,
        string teamId,
        bytes signature,
        string uri
    );

    function safeMintCertificateParticipant(
        uint256 _competitionId,
        string calldata _teamId,
        bytes calldata _signature,
        string calldata _cid
    ) external onlyCompetitionEnd(_competitionId) returns (uint256) {
        if (bytes(_teamId).length == 0) revert InvalidTeamId();

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

        if (!prizesDistributed[w.competitionId]) {
            revert PrizesNotDistributed();
        }

        Competitions storage comp = competitions[w.competitionId];

        if (comp.id == 0) revert CompetitionDoesNotExist();

        if (block.timestamp < comp.prizeCertificateClaim) {
            revert CompetitionNotEnded();
        }

        string memory team = winnerTeamId[_winnerId];

        string memory uri = IPFSHelper.toIPFSURI(_cid);

        bytes32 certId = CertificateHelper.winnerCertId(
            w.competitionId,
            _winnerId,
            team,
            msg.sender,
            _cid
        );

        if (claimedWinnerCertificate[certId]) {
            revert CertificateAlreadyClaimed();
        }

        CompetitionHelper.verifySig(
            keccak256(
                abi.encodePacked(address(this), msg.sender, _winnerId, _cid)
            ),
            signature,
            signerAddress
        );

        claimedWinnerCertificate[certId] = true;

        return
            _mintWinnerCertificate(
                msg.sender,
                w.competitionId,
                _winnerId,
                team,
                signature,
                uri
            );
    }

    function _mintWinnerCertificate(
        address participant,
        uint256 _competitionId,
        uint256 _winnerId,
        string memory teamId,
        bytes calldata signature,
        string memory uri
    ) private returns (uint256 tokenId) {
        tokenId = _nextTokenId++;

        _safeMint(participant, tokenId);
        _setTokenURI(tokenId, uri);

        CertificateHelper.emitWinnerCertificateMinted(
            tokenId,
            participant,
            _competitionId,
            _winnerId,
            teamId,
            signature,
            uri
        );
    }

    // ------------------------- ERC721 OVERRIDES -------------------------

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
}

