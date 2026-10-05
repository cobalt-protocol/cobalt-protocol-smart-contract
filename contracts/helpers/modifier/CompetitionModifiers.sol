// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CompetitionModifiers
/// @notice Base contract containing access-control modifiers for CompetitionManager.
/// @dev Dipisahkan dari CompetitionManager agar logic kompetisi tetap ramping.
///      Menggunakan virtual getters sehingga tidak menduplikasi storage/struct.
abstract contract CompetitionModifiers {
    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error CompetitionDoesNotExist();
    error NotOrganization();
    error CompetitionNotEnded();

    // =============================================================
    //                   VIRTUAL GETTERS (to be overridden)
    // =============================================================

    /// @dev Harus di-override oleh CompetitionManager untuk mengakses `competitions` mapping.
    function _competitionExists(uint256 competitionId) internal view virtual returns (bool);
    function _competitionOrganization(uint256 competitionId) internal view virtual returns (address);
    function _competitionPrizeCertificateClaim(uint256 competitionId) internal view virtual returns (uint256);

    // =============================================================
    //                      MODIFIERS
    // =============================================================

    modifier onlyOrganization(uint256 _competitionId) {
        if (!_competitionExists(_competitionId)) revert CompetitionDoesNotExist();
        if (_competitionOrganization(_competitionId) != msg.sender) revert NotOrganization();
        _;
    }

    modifier onlyCompetitionEnd(uint256 _competitionId) {
        if (!_competitionExists(_competitionId)) revert CompetitionDoesNotExist();
        if (block.timestamp < _competitionPrizeCertificateClaim(_competitionId)) revert CompetitionNotEnded();
        _;
    }
}
