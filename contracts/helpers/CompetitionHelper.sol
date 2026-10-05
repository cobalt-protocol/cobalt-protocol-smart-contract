// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title CompetitionHelper
/// @notice Kumpulan helper internal untuk CompetitionManager:
///         - Validasi token listing yang aktif.
///         - Verifikasi tanda tangan (EIP-191) terhadap signer.
library CompetitionHelper {
    // =============================================================
    //                      ERRORS
    // =============================================================

    error TokenNotListed();
    error TokenNotActive();
    error InvalidSignature();

    // =============================================================
    //                      STRUCTS
    // =============================================================

    struct ListingToken {
        uint256 id;
        address tokenAddress;
        bool isActive;
    }

    // =============================================================
    //                      FUNCTIONS
    // =============================================================

    /// @dev Pastikan token sudah terdaftar dan masih aktif.
    function requireTokenActive(
        ListingToken storage token
    ) internal view {
        if (token.id == 0) revert TokenNotListed();
        if (!token.isActive) revert TokenNotActive();
    }

    /// @dev Validasi tanda tangan terhadap signerAddress.
    function verifySig(
        bytes32 messageHash,
        bytes calldata signature,
        address signerAddress
    ) internal view {
        address recovered = ECDSA.recover(
            MessageHashUtils.toEthSignedMessageHash(messageHash),
            signature
        );
        if (recovered != signerAddress) revert InvalidSignature();
    }
}
