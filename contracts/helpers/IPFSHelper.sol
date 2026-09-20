// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

library IPFSHelper {
    function toIPFSURI(
        string memory cid
    ) internal pure returns (string memory) {
        return string.concat("ipfs://", cid);
    }
}
