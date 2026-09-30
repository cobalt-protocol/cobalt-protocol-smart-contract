import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("certificate_id", type=int)
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, certificate_id, contract_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT") or os.getenv("CERTIFICATE_MANAGER_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and COMPETITION_CONTRACT not set in .env"
        )
        return

    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            akun = accounts.load(account_name)
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        token_symbol = provider.network.ecosystem.fee_token_symbol
        saldo_eth = akun.balance / 10**18

        print(f"Caller      : {akun.address}")
        print(f"Balance     : {saldo_eth} {token_symbol}")

        contract = project.CompetitionManager.at(contract_address)
        print(f"Contract    : {contract.address}")

        print(f"\nFetching certificate participant winner ID {certificate_id}...")

        try:
            cert = contract.certificateParticipantWinner(certificate_id)
        except Exception:
            print(f"Error: Certificate participant winner ID {certificate_id} does not exist.")
            return

        if cert.id == 0:
            print(f"Error: Certificate participant winner ID {certificate_id} does not exist.")
            return

        comp = contract.getCompetition(cert.competitionId)

        print(f"\n{'='*50}")
        print(f"Certificate Participant Winner #{cert.id}")
        print(f"{'='*50}")
        print(f"Certificate ID : {cert.id}")
        print(f"Competition ID : {cert.competitionId}")
        print(f"Participant    : {cert.participant}")
