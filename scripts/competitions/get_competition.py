import os
from datetime import datetime, timezone

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

        print(f"\nFetching competition ID {competition_id}...")
        comp = contract.getCompetition(competition_id)

        if comp.id == 0:
            print(f"Error: Competition ID {competition_id} does not exist.")
            return

        sched = comp.schedule
        claim_ts = sched.prizeCertificateClaim if hasattr(sched, "prizeCertificateClaim") else sched[5]
        end_at_dt = datetime.fromtimestamp(claim_ts, tz=timezone.utc)
        end_at_str = end_at_dt.strftime("%Y-%m-%d %H:%M:%S UTC")

        print(f"\n{'='*50}")
        print(f"Competition #{comp.id}")
        print(f"{'='*50}")
        print(f"Name        : {comp.name}")
        print(f"Category    : {comp.category}")
        print(f"Description : {comp.description}")
        print(f"Requirements: {comp.requirements}")
        print(f"Organization: {comp.organization}")
        print(f"Schedule    :")
        print(f"  Registration Window    : {sched.registrationWindow if hasattr(sched, 'registrationWindow') else sched[0]}")
        print(f"  Competition Window     : {sched.competitionWindow if hasattr(sched, 'competitionWindow') else sched[1]}")
        print(f"  Submission Deadline    : {sched.submissionDeadline if hasattr(sched, 'submissionDeadline') else sched[2]}")
        print(f"  Judging Review         : {sched.judgingReview if hasattr(sched, 'judgingReview') else sched[3]}")
        print(f"  Result Announcement    : {sched.resultAnnouncement if hasattr(sched, 'resultAnnouncement') else sched[4]}")
        print(f"  Prize Certificate Claim: {end_at_str} ({claim_ts})")
        print(f"Certificate : ipfs://{comp.certificateCID}")

        print(f"\n{'='*50}")
        print("Winners")
        print(f"{'='*50}")
        winners_list = contract.getWinners(competition_id)
        if winners_list:
            for index, w in enumerate(winners_list):
                prize_eth = w.prizeAmount / 10**18
                token_label = "Native Token" if w.prizeToken == NATIVE_TOKEN else w.prizeToken
                print(f"  [{index}] {w.title}")
                print(f"    Winner ID   : {w.winnerId}")
                print(f"    Prize Token : {token_label}")
                print(f"    Prize Amount: {prize_eth} ({w.prizeAmount} wei)")
                print(f"    Certificate : ipfs://{w.certificateCID}")
        else:
            print("  No winners found.")
