import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv
from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

load_dotenv()

# Hardcoded CID (raw, tanpa prefix ipfs://) untuk CompetitionManager.safeMintCertificateParticipant(_cid)
# Ganti dengan CID IPFS metadata sertifikat yang valid. Contoh: bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi
HARDCODED_CID = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"


@click.command()
@click.argument("account_name")
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
def cli(account_name, competition_id, team_id, contract_address, network):
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

    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            akun = accounts.load(account_name)
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        token_symbol = provider.network.ecosystem.fee_token_symbol
        saldo_eth = akun.balance / 10**18

        contract = project.CompetitionManager.at(contract_address)

        print(f"Caller               : {akun.address}")
        print(f"Local Signer         : {signer_account.address}")
        print(f"Balance              : {saldo_eth} {token_symbol}")
        print(f"Contract             : {contract.address}")

        if hasattr(contract, "signerAddress"):
            contract_signer = contract.signerAddress()
            print(f"Contract Signer      : {contract_signer}")
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

        if team_id <= 0:
            print("Error: team_id must be a positive integer.")
            return

        # Hardcoded CID — CompetitionManager sekarang butuh _cid eksplisit.
        # Hash = keccak256(abi.encodePacked(address(this), msg.sender, _competitionId, _teamId, _cid)) dengan _cid = HARDCODED_CID.
        # On-chain akan derive URI via IPFSHelper.toIPFSURI(_cid) => ipfs://<cid>.
        effective_cid_raw = HARDCODED_CID.strip().removeprefix("ipfs://").strip()
        if not effective_cid_raw:
            print("Error: HARDCODED_CID kosong — isi konstanta HARDCODED_CID di atas file dengan raw IPFS CID.")
            return
        if comp.certificateCID and effective_cid_raw != comp.certificateCID:
            print(f"Info: Hardcoded CID '{effective_cid_raw}' berbeda dari on-chain competition.certificateCID '{comp.certificateCID}' — hash pakai hardcoded.")

        effective_uri = f"ipfs://{effective_cid_raw}"

        print(f"\n{'='*50}")
        print("Claim Certificate Participant")
        print(f"{'='*50}")
        print(f"Competition    : #{comp.id}")
        print(f"Organization   : {comp.organization}")
        print(f"Participant    : {akun.address}")
        print(f"Team ID        : {team_id}")
        print(f"Certificate CID (raw _cid): {effective_cid_raw or '(empty)'}")
        print(f"Certificate URI (on-chain): {effective_uri}")

        print("\nGenerating signature from PRIVATE_KEY_SIGNER...")
        contract_checksum = Web3.to_checksum_address(contract.address)
        caller_checksum = Web3.to_checksum_address(akun.address)

        # Must match CompetitionManager.safeMintCertificateParticipant hash which now uses explicit _cid param.
        # keccak256(abi.encodePacked(address(this), msg.sender, _competitionId, _teamId, _cid)) where _cid is raw CID.
        # Also matches API hashParticipantCertificate() which hashes freshly pinned metadata CID.
        # Use --cid <metadataCidRaw> to reproduce API sig exactly.
        msg_hash = Web3.solidity_keccak(
            ["address", "address", "uint256", "uint256", "string"],
            [contract_checksum, caller_checksum, competition_id, team_id, effective_cid_raw],
        )
        signable_msg = encode_defunct(primitive=msg_hash)
        signed_msg = signer_account.sign_message(signable_msg)
        signature = signed_msg.signature

        print("Minting certificate with signature...")
        print(f"Calling safeMintCertificateParticipant({competition_id}, {team_id}, sig, _cid='{effective_cid_raw}')")

        tx = contract.safeMintCertificateParticipant(
            competition_id,
            team_id,
            signature,
            effective_cid_raw,
            sender=akun,
        )

        print(f"\nTX Hash        : {tx.txn_hash}")
        print("Claim certificate participant success!")



