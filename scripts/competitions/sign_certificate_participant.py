import os

import click
from ape import networks, project
from dotenv import load_dotenv
from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

load_dotenv()


@click.command()
@click.argument("participant_address")
@click.argument("competition_id", type=int)
@click.option(
    "--team-id",
    "team_id",
    type=int,
    required=True,
    help="Team ID of the participant",
)
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(participant_address, competition_id, team_id, contract_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT") or os.getenv("CERTIFICATE_COMPETITION_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and COMPETITION_CONTRACT not set in .env"
        )
        return

    private_key_signer = os.getenv("PRIVATE_KEY_SIGNER")
    if not private_key_signer:
        print("Error: PRIVATE_KEY_SIGNER is not set in .env")
        return

    signer_account = Account.from_key(private_key_signer)

    # Validate participant address early
    try:
        participant_checksum_early = Web3.to_checksum_address(participant_address)
    except Exception:
        print(f"Error: Invalid participant address '{participant_address}'")
        return

    if team_id <= 0:
        print("Error: --team-id must be a positive integer.")
        return

    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        contract = project.CompetitionManager.at(contract_address)
        contract_signer = contract.signerAddress()

        print(f"Local Signer         : {signer_account.address}")
        print(f"Contract Signer      : {contract_signer}")
        print(f"Contract             : {contract.address}")
        print(f"Participant          : {participant_checksum_early}")

        if signer_account.address.lower() != contract_signer.lower():
            print(
                f"\nError: Local signer ({signer_account.address}) does NOT match contract signer ({contract_signer})!"
            )
            print("Please update signerAddress on CompetitionManager.")
            return

        print(f"\nFetching competition ID {competition_id}...")
        comp = contract.getCompetition(competition_id)

        if comp.id == 0:
            print(f"Error: Competition ID {competition_id} does not exist.")
            return

        ended = contract.isCompetitionEnded(competition_id)
        if not ended:
            print(f"Error: Competition ID {competition_id} has not ended yet.")
            return

        certificate_uri = comp.certificateCID if comp.certificateCID else ""
        # NOTE: raw CID only — matches CompetitionManager.safeMintCertificateParticipant hash (cid, not ipfs:// uri)

        if not comp.certificateCID:
            print("Warning: Competition certificateCID is empty, using empty CID.")

        print(f"\n{'='*50}")
        print("Sign Certificate Participant")
        print(f"{'='*50}")
        print(f"Competition    : #{comp.id}")
        print(f"Organization   : {comp.organization}")
        print(f"Participant    : {participant_checksum_early}")
        print(f"Team ID        : {team_id}")
        print(f"Certificate URI: {certificate_uri}")

        print("\nGenerating signature from PRIVATE_KEY_SIGNER...")
        contract_checksum = Web3.to_checksum_address(contract.address)
        participant_checksum = Web3.to_checksum_address(participant_address)

        # Must match CompetitionManager.safeMintCertificateParticipant:
        # keccak256(abi.encodePacked(
        #   address(this),
        #   msg.sender,
        #   _competitionId,
        #   _teamId,
        #   cid
        # ))
        # where cid = competition.certificateCID raw (no ipfs:// prefix)
        # verified via CompetitionHelper.verifySig -> ECDSA.recover(toEthSignedMessageHash(hash), sig)
        # NOTE: single msg.sender — duplicate was a copy-paste bug, wastes gas & causes mismatch if not synced.
        msg_hash = Web3.solidity_keccak(
            ["address", "address", "uint256", "uint256", "string"],
            [contract_checksum, participant_checksum, competition_id, team_id, certificate_uri],
        )
        signable_msg = encode_defunct(primitive=msg_hash)
        signed_msg = signer_account.sign_message(signable_msg)
        sig_hex = signed_msg.signature.hex()
        signature_formatted = sig_hex if sig_hex.startswith("0x") else f"0x{sig_hex}"

        print(f"\nSignature      : {signature_formatted}")
        print("Signature generated successfully!")


if __name__ == "__main__":
    cli()
