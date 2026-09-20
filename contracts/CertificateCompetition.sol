// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "./CompetitionManager.sol";
import "./CertificateManager.sol";
import "./SignerManager.sol";

contract CertificateCompetition is ERC721, ERC721URIStorage, Ownable {
    CompetitionManager public competitionManagerContract;
    CertificateManager public certificateManagerContract;
    SignerManager public signerManagerContract;
    SignerManager public signerManagerCertificateContract;

    uint256 private _nextTokenId;

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

    constructor(
        address initialOwner,
        address _signerAddress
    ) ERC721("Certificate Competition", "CC") Ownable(initialOwner) {
        signerManagerContract = new SignerManager(initialOwner, _signerAddress);

        signerManagerCertificateContract = new SignerManager(initialOwner, _signerAddress);

        competitionManagerContract = new CompetitionManager(initialOwner);

        certificateManagerContract = new CertificateManager(
            address(this),
            address(competitionManagerContract),
            address(signerManagerCertificateContract)
        );
    }

    modifier onlyCompetitionEnd(uint256 _competitionId) {
        CompetitionManager.Competitions
            memory competition = competitionManagerContract.getCompetition(
                _competitionId
            );

        require(competition.id != 0, "Competition does not exist");

        require(
            block.timestamp >= competition.endAt,
            "Competition is not ended"
        );

        _;
    }

    function _toIPFSURI(
        string memory cid
    ) internal pure returns (string memory) {
        return string.concat("ipfs://", cid);
    }

    function safeMintCertificateParticipant(
        uint256 _competitionId,
        bytes memory signature
    ) public onlyCompetitionEnd(_competitionId) returns (uint256) {
        require(
            !certificateManagerContract.hasCertificateParticipant(
                msg.sender,
                _competitionId
            ),
            "Certificate participant already claimed"
        );

        CompetitionManager.Competitions
            memory competition = competitionManagerContract.getCompetition(
                _competitionId
            );

        string memory uri = _toIPFSURI(competition.certificateCID);

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
            recoveredSigner == signerManagerContract.signerAddress(),
            "Invalid signature"
        );

        uint256 tokenId = _nextTokenId++;

        _safeMint(msg.sender, tokenId);

        _setTokenURI(tokenId, uri);

        certificateManagerContract.addCertificateParticipant(
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
        CompetitionManager.Winners memory winner = competitionManagerContract
            .getWinner(_winnerId);

        CompetitionManager.Competitions
            memory competition = competitionManagerContract.getCompetition(
                winner.competitionId
            );

        require(competition.id != 0, "Competition does not exist");

        require(
            block.timestamp >= competition.endAt,
            "Competition is not ended"
        );

        require(
            !certificateManagerContract.hasCertificateParticipantWinner(
                msg.sender,
                _winnerId
            ),
            "Certificate participant winner already claimed"
        );

        string memory uri = _toIPFSURI(winner.certificateCID);

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
            recoveredSigner == signerManagerContract.signerAddress(),
            "Invalid signature"
        );

        uint256 tokenId = _nextTokenId++;

        _safeMint(msg.sender, tokenId);

        _setTokenURI(tokenId, uri);

        certificateManagerContract.addCertificateParticipantWinner(
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
