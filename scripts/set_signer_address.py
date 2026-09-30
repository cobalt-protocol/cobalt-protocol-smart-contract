import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("new_signer_address")
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, new_signer_address, contract_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT") or os.getenv("CERTIFICATE_COMPETITION_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and COMPETITION_CONTRACT not set in .env"
        )
        return

    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            owner_account = accounts.load(account_name)
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        token_symbol = provider.network.ecosystem.fee_token_symbol
        saldo_eth = owner_account.balance / 10**18

        print(f"Caller             : {owner_account.address}")
        print(f"Balance            : {saldo_eth} {token_symbol}")
        print(f"New Signer Address : {new_signer_address}")

        contract = project.CompetitionManager.at(contract_address)

        old_signer = contract.signerAddress()
        print(f"\nContract Address   : {contract.address}")
        print(f"Current Signer     : {old_signer}")
        if old_signer.lower() == new_signer_address.lower():
            print("Signer address is already set to the new address.")
        else:
            print("Updating signer address on CompetitionManager...")
            tx = contract.updateSignerAddress(new_signer_address, sender=owner_account)
            print(f"TX Hash            : {tx.txn_hash}")
            print(f"Updated Signer     : {contract.signerAddress()}")

        print("\nSigner address update task finished!")

