import json

import click
from ape import accounts, networks, project


@click.command()
@click.argument("account_name")
@click.argument("contract_address")
@click.argument("input_json", type=click.Path(exists=True))
@click.option("--network", help="Network specifier")
def cli(account_name, contract_address, input_json, network):
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

        with open(input_json, "r") as f:
            data = json.load(f)

        competition = data["competition"]
        prizes_data = data["prizes"]

        competition_input = (
            competition["title"],
            competition["category"],
            competition["description"],
            competition["participationRequirement"],
            competition["durationInDays"],
            competition["guidebookCID"],
            competition["participantCertCID"],
        )

        total_prize_pool = 0
        prize_inputs = []
        for p in prizes_data:
            amount_wei = int(p["amount"] * 10**18)
            total_prize_pool += amount_wei
            prize_inputs.append(
                (
                    p["rank"],
                    p["title"],
                    amount_wei,
                    p["winnerCertCID"],
                )
            )

        fee = contract.competitionFee()
        total_value = fee + total_prize_pool

        fee_eth = fee / 10**18
        pool_eth = total_prize_pool / 10**18
        total_eth = total_value / 10**18

        print(f"\n{'='*50}")
        print("Competition Details")
        print(f"{'='*50}")
        print(f"Title       : {competition['title']}")
        print(f"Category    : {competition['category']}")
        print(f"Description : {competition['description']}")
        print(f"Requirement : {competition['participationRequirement']}")
        print(f"Duration    : {competition['durationInDays']} days")
        print(f"Guidebook   : ipfs://{competition['guidebookCID']}")
        print(f"Participant Cert : ipfs://{competition['participantCertCID']}")

        print(f"\nPrizes ({len(prize_inputs)}):")
        print(f"{'-'*50}")
        for p in prizes_data:
            print(f"  Rank {p['rank']}: {p['title']}")
            print(f"    Amount   : {p['amount']} {token_symbol}")
            print(f"    Cert CID : ipfs://{p['winnerCertCID']}")

        print(f"\n{'='*50}")
        print("Cost Breakdown")
        print(f"{'='*50}")
        print(f"Fee         : {fee_eth} {token_symbol}")
        print(f"Prize Pool  : {pool_eth} {token_symbol}")
        print(f"Total       : {total_eth} {token_symbol}")

        print("\nCreating competition...")
        tx = contract.createCompetition(
            competition_input,
            prize_inputs,
            sender=akun,
            value=total_value,
        )

        competition_id = tx.return_value
        print(f"\nCompetition ID : {competition_id}")
        print(f"TX Hash        : {tx.txn_hash}")
        print("Create success!")
