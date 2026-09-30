import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("new_owner_address")
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, new_owner_address, contract_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT") or os.getenv("TREASURY_PLATFORM_CONTRACT")
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
        print(f"Old Owner   : {contract.owner()}")
        print(f"New Owner   : {new_owner_address}")

        print("\nUpdating CompetitionManager owner...")
        tx = contract.updateOwner(new_owner_address, sender=akun)

        print(f"TX Hash     : {tx.txn_hash}")
        print(f"New Owner   : {contract.owner()}")
        print("Update owner success!")
