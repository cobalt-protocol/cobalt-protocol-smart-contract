import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv
from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("winner_id", type=int)
@click.option(
    "--cid",
    "certificate_cid",
    default=None,
    help="Raw IPFS CID for _cid param (without ipfs://). If omitted, falls back to winner.certificateCID on-chain (backward compat).",
)
@click.option(
    "--certificate-cid",
    "certificate_cid_alias",
    default=None,
    hidden=True,
)
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, winner_id, certificate_cid, certificate_cid_alias, contract_address, network):
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
        contract_signer = contract.signerAddress()

        print(f"Caller               : {akun.address}")
        print(f"Local Signer         : {signer_account.address}")
        print(f"Contract Signer      : {contract_signer}")
        print(f"Balance              : {saldo_eth} {token_symbol}")
        print(f"Contract             : {contract.address}")

        if signer_account.address.lower() != contract_signer.lower():
            print(
                f"\nError: Local signer ({signer_account.address}) does NOT match contract signer ({contract_signer})!"
            )
            print("Please update signerAddress on CompetitionManager.")
            return

        print(f"\nFetching winner ID {winner_id}...")
        try:
            winner = contract.getWinner(winner_id)
        except Exception:
            print(f"Error: Winner ID {winner_id} does not exist.")
            return

        comp = contract.getCompetition(winner.competitionId)

        if comp.id == 0:
            print(f"Error: Competition ID {winner.competitionId} does not exist.")
            return

        ended = contract.isCompetitionEnded(winner.competitionId)
        if not ended:
            print(f"Error: Competition ID {winner.competitionId} has not ended yet.")
            return

        # Resolve effective _cid (raw, without ipfs://) for safeMintCertificateParticipantWinner(_cid).
        # New contract: certId = keccak256(abi.encodePacked(_competitionId, _teamId, msg.sender, _cid))
        # and hash = keccak256(abi.encodePacked(address(this), msg.sender, _winnerId, uri))
        # where uri = IPFSHelper.toIPFSURI(_cid) = "ipfs://" + _cid.
        # Priority: explicit --cid / --certificate-cid > on-chain winner.certificateCID.
        explicit_raw = (certificate_cid if certificate_cid is not None else certificate_cid_alias) or ""
        explicit_raw = explicit_raw.strip()
        if explicit_raw.startswith("ipfs://"):
            explicit_raw = explicit_raw[7:].strip()

        if explicit_raw:
            effective_cid_raw = explicit_raw
            if winner.certificateCID and explicit_raw != winner.certificateCID:
                print(f"Info: Using explicit --cid '{effective_cid_raw}' (differs from on-chain winner.certificateCID '{winner.certificateCID}').")
        else:
            effective_cid_raw = winner.certificateCID if winner.certificateCID else ""
            if not winner.certificateCID:
                print("Warning: winner.certificateCID is empty and no --cid provided, using empty _cid.")
            else:
                print(f"Info: --cid not provided, using on-chain winner.certificateCID: {effective_cid_raw}")

        effective_uri = f"ipfs://{effective_cid_raw}" if effective_cid_raw else ""

        print(f"\n{'='*50}")
        print("Claim Certificate Participant Winner")
        print(f"{'='*50}")
        print(f"Competition    : #{comp.id}")
        print(f"Winner ID      : #{winner.id}")
        print(f"Organization   : {comp.organization}")
        print(f"Participant    : {akun.address}")
        print(f"Certificate CID (raw _cid): {effective_cid_raw or '(empty)'}")
        print(f"Certificate URI (on-chain): {effective_uri}")

        print("\nGenerating signature from PRIVATE_KEY_SIGNER...")
        contract_checksum = Web3.to_checksum_address(contract.address)
        caller_checksum = Web3.to_checksum_address(akun.address)

        # Must match CompetitionManager.safeMintCertificateParticipantWinner:
        # keccak256(abi.encodePacked(address(this), msg.sender, _winnerId, uri)) where uri = ipfs:// + _cid
        # Also matches API hashWinnerCertificate() in certificate-signature.util.ts
        msg_hash = Web3.solidity_keccak(
            ["address", "address", "uint256", "string"],
            [contract_checksum, caller_checksum, winner_id, effective_uri],
        )
        signable_msg = encode_defunct(primitive=msg_hash)
        signed_msg = signer_account.sign_message(signable_msg)
        signature = signed_msg.signature

        print("Minting certificate with signature...")
        print(f"Calling safeMintCertificateParticipantWinner({winner_id}, sig, _cid='{effective_cid_raw}')")

        tx = contract.safeMintCertificateParticipantWinner(
            winner_id,
            signature,
            effective_cid_raw,
            sender=akun,
        )

        print(f"\nTX Hash        : {tx.txn_hash}")
        print("Claim certificate participant winner success!")

