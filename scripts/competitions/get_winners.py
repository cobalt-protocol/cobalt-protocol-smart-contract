import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


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

        print(f"\nFetching winners for Competition ID {competition_id}...")
        winners_list = contract.getWinners(competition_id)

        print(f"\n{'='*50}")
        print(f"Winners (Competition #{competition_id})")
        print(f"{'='*50}")

        if winners_list:
            for i, w in enumerate(winners_list):
                prize_eth = w.prizeAmount / 10**18
                token_label = "Native Token" if w.prizeToken == NATIVE_TOKEN else w.prizeToken
                print(f"  [{i}] Winner #{w.id}")
                print(f"    Winner ID   : {w.id}")
                print(f"    Prize Token : {token_label}")
                print(f"    Prize Amount: {prize_eth} ({w.prizeAmount} wei)")
                print(f"    Certificate : ipfs://{w.certificateCID}")
        else:
            print("  No winners found.")
