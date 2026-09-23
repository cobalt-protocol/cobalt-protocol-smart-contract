import os

import click
from ape import accounts, networks, project, Contract
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


@click.command()
@click.argument("account_name")
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: TREASURY_PLATFORM_CONTRACT from .env)",
)
@click.option(
    "--token",
    "token_address",
    default=NATIVE_TOKEN,
    help="Token address to check balance for (default: native token)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, contract_address, token_address, network):
    contract_address = contract_address or os.getenv("TREASURY_PLATFORM_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and TREASURY_PLATFORM_CONTRACT not set in .env"
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

        contract = project.TreasuryPlatform.at(contract_address)
        print(f"Contract    : {contract.address}")

        owner_address = contract.owner()

        if token_address == NATIVE_TOKEN:
            print("Token       : Native Token")
        else:
            print(f"Token       : {token_address}")

        print(f"Owner       : {owner_address}")

        print(f"\nFetching treasury balance...")

        if token_address == NATIVE_TOKEN:
            owner_balance = provider.get_balance(owner_address)
            contract_balance = provider.get_balance(contract.address)
        else:
            erc20 = Contract(token_address)
            owner_balance = erc20.balanceOf(owner_address)
            contract_balance = erc20.balanceOf(contract.address)

        owner_balance_eth = owner_balance / 10**18
        contract_balance_eth = contract_balance / 10**18

        print(f"\n{'='*50}")
        print("Treasury Balance")
        print(f"{'='*50}")
        print(f"  Owner Address    : {owner_address}")
        print(f"  Owner Balance    : {owner_balance_eth} {token_symbol} ({owner_balance} wei)")
        print(f"  Contract Address : {contract.address}")
        print(f"  Contract Balance : {contract_balance_eth} {token_symbol} ({contract_balance} wei)")
