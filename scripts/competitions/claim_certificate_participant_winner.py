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
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: CERTIFICATE_COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, winner_id, contract_address, network):
    contract_address = contract_address or os.getenv("CERTIFICATE_COMPETITION_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and CERTIFICATE_COMPETITION_CONTRACT not set in .env"
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

        contract = project.CertificateCompetition.at(contract_address)
        signer_manager_address = contract.signerManagerContract()
        signer_manager = project.SignerManager.at(signer_manager_address)
        contract_signer = signer_manager.signerAddress()

        signer_manager_cert_address = contract.signerManagerCertificateContract()
        signer_manager_cert = project.SignerManager.at(signer_manager_cert_address)
        contract_signer_cert = signer_manager_cert.signerAddress()

        print(f"Caller               : {akun.address}")
        print(f"Local Signer         : {signer_account.address}")
        print(f"Contract Signer      : {contract_signer}")
        print(f"Cert Contract Signer : {contract_signer_cert}")
        print(f"Balance              : {saldo_eth} {token_symbol}")
        print(f"Contract             : {contract.address}")

        if signer_account.address.lower() != contract_signer.lower():
            print(
                f"\nError: Local signer ({signer_account.address}) does NOT match contract signer ({contract_signer})!"
            )
            print("Please redeploy the contract with --signer argument or update signerAddress on SignerManager.")
            return

        if signer_account.address.lower() != contract_signer_cert.lower():
            print(
                f"\nError: Local signer ({signer_account.address}) does NOT match certificate contract signer ({contract_signer_cert})!"
            )
            print("Please redeploy the contract with --signer argument or update signerAddress on SignerManagerCertificate.")
            return

        competition_manager_address = contract.competitionManagerContract()
        competition_contract = project.CompetitionManager.at(competition_manager_address)

        print(f"\nFetching winner ID {winner_id}...")
        try:
            winner = competition_contract.getWinner(winner_id)
        except Exception:
            print(f"Error: Winner ID {winner_id} does not exist.")
            return

        comp = competition_contract.getCompetition(winner.competitionId)

        if comp.id == 0:
            print(f"Error: Competition ID {winner.competitionId} does not exist.")
            return

        ended = competition_contract.isCompetitionEnded(winner.competitionId)
        if not ended:
            print(f"Error: Competition ID {winner.competitionId} has not ended yet.")
            return

        certificate_uri = f"ipfs://{winner.certificateCID}"

        print(f"\n{'='*50}")
        print("Claim Certificate Participant Winner")
        print(f"{'='*50}")
        print(f"Competition    : #{comp.id} - {comp.name}")
        print(f"Winner ID      : #{winner.winnerId} - {winner.title}")
        print(f"Organization   : {comp.organization}")
        print(f"Participant    : {akun.address}")
        print(f"Certificate URI: {certificate_uri}")

        print("\nGenerating signature from PRIVATE_KEY_SIGNER...")
        contract_checksum = Web3.to_checksum_address(contract.address)
        caller_checksum = Web3.to_checksum_address(akun.address)

        msg_hash = Web3.solidity_keccak(
            ["address", "address", "address", "uint256", "string"],
            [contract_checksum, caller_checksum, caller_checksum, winner_id, certificate_uri],
        )
        signable_msg = encode_defunct(primitive=msg_hash)
        signed_msg = signer_account.sign_message(signable_msg)
        signature = signed_msg.signature

        print("Minting certificate with signature...")

        tx = contract.safeMintCertificateParticipantWinner(
            winner_id,
            signature,
            sender=akun,
        )

        print(f"\nTX Hash        : {tx.txn_hash}")
        print("Claim certificate participant winner success!")

