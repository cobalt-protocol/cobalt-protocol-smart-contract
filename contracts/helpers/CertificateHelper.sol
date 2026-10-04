// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

library CertificateHelper {
    /// @dev Bangun composite key anti double-claim.
    function certId(
        uint256 _competitionId,
        uint256 _teamId,
        address _wallet
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_competitionId, _teamId, _wallet));
    }
}
