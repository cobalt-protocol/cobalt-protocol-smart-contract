// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import "./CompetitionManager.sol";
import "./SignerManager.sol";
import {IPFSHelper} from "./helpers/IPFSHelper.sol";

contract CertificateManager is Ownable {
    CompetitionManager public competitionManagerContract;
    SignerManager public signerManagerContract;

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

    uint256 private certificateParticipantId;
    uint256 private certificateParticipantWinnerId;

    mapping(uint256 => CertificateParticipant) public certificateParticipant;
    mapping(uint256 => CertificateParticipantWinner)
        public certificateParticipantWinner;

    mapping(address => mapping(uint256 => bool))
        public hasCertificateParticipant;
    mapping(address => mapping(uint256 => bool))
        public hasCertificateParticipantWinner;

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

    constructor(
        address initialOwner,
        address _competitionManagerAddress,
        address _signerManagerAddress
    ) Ownable(initialOwner) {
        competitionManagerContract = CompetitionManager(
            _competitionManagerAddress
        );
        signerManagerContract = SignerManager(_signerManagerAddress);
    }

    function addCertificateParticipant(
        address _participant,
        uint256 _competitionId,
        bytes memory signature
    ) external {
        CompetitionManager.Competitions
            memory comp = competitionManagerContract.getCompetition(
                _competitionId
            );

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
            recoveredSigner == signerManagerContract.signerAddress(),
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
    ) external {
        CompetitionManager.Competitions
            memory comp = competitionManagerContract.getCompetition(
                _competitionId
            );

        require(comp.id != 0, "Competition does not exist");

        require(
            !hasCertificateParticipantWinner[_participant][_winnerId],
            "Certificate participant winner already exists"
        );

        CompetitionManager.Winners memory winner = competitionManagerContract
            .getWinner(_winnerId);

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
            recoveredSigner == signerManagerContract.signerAddress(),
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
}

