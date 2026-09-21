import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.option("--fee-id", "platform_fee_id", default=1, type=int, help="Platform fee ID (default: 1)")
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: PRICE_COMPETITION_MANAGER_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, platform_fee_id, contract_address, network):
    contract_address = contract_address or os.getenv("PRICE_COMPETITION_MANAGER_CONTRACT") or os.getenv("PRIZE_COMPETITION_MANAGER_CONTRACT") or os.getenv("FEE_MANAGER_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and PRICE_COMPETITION_MANAGER_CONTRACT not set in .env"
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

        contract = project.PriceCompetitionManager.at(contract_address)
        print(f"Contract    : {contract.address}")

        fee = contract.getPriceCompetitionFee(platform_fee_id)
        if fee.id == 0:
            print(f"\nFee Option ID #{platform_fee_id} does not exist.")
            return

        print(f"\n{'='*50}")
        print(f"PriceCompetitionManager Option #{fee.id}")
        print(f"{'='*50}")
        print(f"  Title        : {fee.title}")
        print(f"  Description  : {fee.description}")
        print(f"  Token Address: {fee.tokenAddress}")
        print(f"  Treasury Fee : {fee.treasuryFee / 10**18} {token_symbol} ({fee.treasuryFee} wei)")

