// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SignerManager is Ownable {
    address public signerAddress;

    event SignerAddressSet(address indexed signerAddress);

    constructor(
        address initialOwner,
        address _signerAddress
    ) Ownable(initialOwner) {
        signerAddress = _signerAddress;
    }

    function setSignerAddress(address _signerAddress) external onlyOwner {
        signerAddress = _signerAddress;
        emit SignerAddressSet(_signerAddress);
    }
}
