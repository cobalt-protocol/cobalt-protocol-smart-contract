import click
from ape import accounts, networks, project


@click.command()
@click.argument("account_name")
@click.argument("contract_address")
@click.argument("competition_id", type=int)
@click.option("--network", help="Network specifier")
def cli(account_name, contract_address, competition_id, network):
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

        contract = project.EventCompetition.at(contract_address)
        print(f"Contract    : {contract.address}")

        print(f"\nFetching competition ID {competition_id}...")
        comp = contract.getCompetition(competition_id)

        print(f"\n{'='*50}")
        print(f"Competition #{comp.id}")
        print(f"{'='*50}")
        print(f"Title       : {comp.title}")
        print(f"Category    : {comp.category}")
        print(f"Description : {comp.description}")
        print(f"Requirement : {comp.participationRequirement}")
        print(f"Organizer   : {comp.organizer}")
        print(f"Start Time  : {comp.startTime}")
        print(f"End Time    : {comp.endTime}")
        print(f"Guidebook   : ipfs://{comp.guidebookCID}")
        print(f"Participant Cert : ipfs://{comp.participantCertCID}")
        print(f"Finalized   : {comp.isFinalized}")

        if comp.prizes:
            print(f"\nPrizes ({len(comp.prizes)}):")
            print(f"{'-'*50}")
            for prize in comp.prizes:
                amount_eth = prize.amount / 10**18
                print(f"  Rank {prize.rank}: {prize.title}")
                print(f"    Amount   : {amount_eth} {token_symbol}")
                print(f"    Cert CID : ipfs://{prize.winnerCertCID}")
        else:
            print("\nNo prizes found.")
