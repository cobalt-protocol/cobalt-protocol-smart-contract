import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("treasury_fee_wei", type=int)
@click.option("--title", default="Standard Fee", help="Title for the fee option")
@click.option("--description", default="Standard platform fee", help="Description for the fee option")
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: FEE_MANAGER_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, treasury_fee_wei, title, description, contract_address, network):
    contract_address = contract_address or os.getenv("FEE_MANAGER_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and FEE_MANAGER_CONTRACT not set in .env"
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

        print(f"Caller           : {akun.address}")
        print(f"Balance          : {saldo_eth} {token_symbol}")

        contract = project.FeeManager.at(contract_address)
        print(f"Contract         : {contract.address}")
        print(f"Title            : {title}")
        print(f"Description      : {description}")
        print(f"New Treasury Fee : {treasury_fee_wei / 10**18} ({treasury_fee_wei} wei)")

        print("\nAdding fee option on FeeManager...")
        tx = contract.setFees(treasury_fee_wei, title, description, sender=akun)

        print(f"TX Hash          : {tx.txn_hash}")
        print("Set fees success!")

