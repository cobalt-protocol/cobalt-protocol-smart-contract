import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


@click.command()
@click.argument("account_name")
@click.argument("competition_id", type=int)
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: TREASURY_PRIZE_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, competition_id, contract_address, network):
    contract_address = contract_address or os.getenv("TREASURY_PRIZE_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and TREASURY_PRIZE_CONTRACT not set in .env"
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

        contract = project.TreasuryPrize.at(contract_address)
        print(f"Contract    : {contract.address}")

        print(f"\nFetching treasury prize for Competition ID {competition_id}...")
        tp = contract.treasuryPrizeByCompetitionId(competition_id)

        if tp.organization == "0x0000000000000000000000000000000000000000":
            print(f"Error: Treasury prize for Competition ID {competition_id} does not exist.")
            return

        prize_eth = tp.totalPrize / 10**18
        token_label = "Native Token" if tp.tokenAddress == NATIVE_TOKEN else tp.tokenAddress

        print(f"\n{'='*50}")
        print(f"Treasury Prize (Competition #{competition_id})")
        print(f"{'='*50}")
        print(f"  Treasury Prize ID: {tp.id}")
        print(f"  Competition ID   : {tp.competitionId}")
        print(f"  Organization     : {tp.organization}")
        print(f"  Token Address    : {token_label}")
        print(f"  Total Prize      : {prize_eth} ({tp.totalPrize} wei)")
