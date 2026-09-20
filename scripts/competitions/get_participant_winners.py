import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("winner_id", type=int)
@click.option("--contract", "contract_address", default=None, help="Contract address (default: COMPETITION_CONTRACT from .env)")
@click.option("--network", help="Network specifier")
def cli(account_name, winner_id, contract_address, network):
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

        print(f"\nFetching participant winners for Winner ID {winner_id}...")
        participant_winners = contract.getParticipantWinners(winner_id)

        print(f"\n{'='*50}")
        print(f"Participant Winners (Winner ID #{winner_id})")
        print(f"{'='*50}")

        if participant_winners:
            for i, pw in enumerate(participant_winners):
                print(f"  [{i}] ID: {pw.participantWinnerId}")
                print(f"    Winner ID   : {pw.winnerId}")
                print(f"    Participant : {pw.participant}")
        else:
            print("  No participant winners found.")
