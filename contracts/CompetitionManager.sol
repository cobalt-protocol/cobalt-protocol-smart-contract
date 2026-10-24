// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {PlatformConfigModule} from "./modules/PlatformConfigModule.sol";
import {TeamPaymentModule} from "./modules/TeamPaymentModule.sol";
import {CompetitionCreationModule} from "./modules/CompetitionCreationModule.sol";
import {PrizeModule} from "./modules/PrizeModule.sol";
import {CertificateModule} from "./modules/CertificateModule.sol";

/// @title CompetitionManager
/// @notice Satu contract address; logika dipecah menjadi modul abstract:
///         - PlatformConfigModule : signer, token listing, platform fee
///         - CompetitionCreationModule: createCompetition + getter
///         - TeamPaymentModule    : escrow biaya tim
///         - PrizeModule          : setWinner + distributePrizes
///         - CertificateModule    : NFT sertifikat (non-transferable)
contract CompetitionManager is
    PlatformConfigModule,
    CompetitionCreationModule,
    TeamPaymentModule,
    PrizeModule,
    CertificateModule
{
    event NativeReceived(address indexed sender, uint256 amount);

    constructor(
        address initialOwner,
        address _signerAddress
    ) ERC721("Certificate Competition", "CC") Ownable(initialOwner) {
        signerAddress = _signerAddress;
    }

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
}
