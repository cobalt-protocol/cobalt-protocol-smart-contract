// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

library FormationHelper {
    string internal constant FORMATION_1_3_MEMBER = "1-3 member";
    string internal constant FORMATION_1_5_MEMBER = "1-5 member";

    /// @dev Validasi formasi kompetisi yang didukung.
    function isValidFormation(
        string memory _formation
    ) internal pure returns (bool) {
        return
            keccak256(bytes(_formation)) ==
            keccak256(bytes(FORMATION_1_3_MEMBER)) ||
            keccak256(bytes(_formation)) ==
            keccak256(bytes(FORMATION_1_5_MEMBER));
    }
}
