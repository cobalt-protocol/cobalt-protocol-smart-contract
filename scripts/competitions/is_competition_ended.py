import os
from datetime import datetime, timezone

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("competition_id", type=int)
@click.option("--contract", "contract_address", default=None, help="Contract address (default: COMPETITION_CONTRACT from .env)")
@click.option("--network", help="Network specifier")
def cli(account_name, competition_id, contract_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT")
    if not contract_address:
        print("Error: Contract address not provided and COMPETITION_CONTRACT not set in .env")
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

        print(f"\nChecking if competition ID {competition_id} has ended...")
        comp = contract.getCompetition(competition_id)

        if comp.id == 0:
            print(f"Error: Competition ID {competition_id} does not exist.")
            return

        ended = contract.isCompetitionEnded(competition_id)
        end_at_dt = datetime.fromtimestamp(comp.endAt, tz=timezone.utc)

        print(f"\n{'='*50}")
        print(f"Competition #{competition_id} Status")
        print(f"{'='*50}")
        print(f"  Name    : {comp.name}")
        print(f"  End At  : {end_at_dt.strftime('%Y-%m-%d %H:%M:%S UTC')} ({comp.endAt})")
        print(f"  Ended   : {'Yes' if ended else 'No'}")
