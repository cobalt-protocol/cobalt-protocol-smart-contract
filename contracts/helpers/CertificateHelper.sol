// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

library CertificateHelper {
    /// @dev Bangun composite key anti double-claim untuk sertifikat peserta.
    function certId(
        uint256 _competitionId,
        string memory _teamId,
        address _wallet,
        string memory _cid
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(_competitionId, _teamId, _wallet, _cid));
    }

    /// @dev Bangun composite key anti double-claim untuk sertifikat pemenang.
    function winnerCertId(
        uint256 _competitionId,
        uint256 _winnerId,
        string memory _teamId,
        address _wallet,
        string memory _cid
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _competitionId,
                    _winnerId,
                    _teamId,
                    _wallet,
                    _cid
                )
            );
    }

    event CertificateParticipantWinnerMinted(
        uint256 indexed tokenId,
        address indexed participant,
        uint256 indexed competitionId,
        uint256 winnerId,
        string teamId,
        bytes signature,
        string uri
    );

    /// @dev Emit event sertifikat pemenang setelah proses mint selesai.
    function emitWinnerCertificateMinted(
        uint256 tokenId,
        address participant,
        uint256 _competitionId,
        uint256 _winnerId,
        string memory teamId,
        bytes calldata signature,
        string memory uri
    ) internal {
        emit CertificateParticipantWinnerMinted(
            tokenId,
            participant,
            _competitionId,
            _winnerId,
            teamId,
            signature,
            uri
        );
    }
}
