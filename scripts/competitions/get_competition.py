#!/usr/bin/env python3
import json
import os
from datetime import datetime, timezone

import click
import requests
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


def fetch_from_kubo_ipfs(cid: str) -> dict:
    if not cid:
        return {}
    base_url = os.getenv("KUBO_API_URL", "http://localhost:5001").rstrip("/")
    endpoint = f"{base_url}/api/v0/cat?arg={cid}"
    try:
        res = requests.post(endpoint, timeout=5)
        if res.ok:
            return res.json()
    except Exception:
        pass
    return {}


def display_competition(contract, comp):
    if comp.id == 0:
        return

    claim_ts = comp.prizeCertificateClaim
    end_at_dt = datetime.fromtimestamp(claim_ts, tz=timezone.utc)
    end_at_str = end_at_dt.strftime("%Y-%m-%d %H:%M:%S UTC")

    meta = fetch_from_kubo_ipfs(comp.cid) if hasattr(comp, "cid") and comp.cid else {}

    print(f"\n{'='*50}")
    print(f"Competition #{comp.id}")
    print(f"{'='*50}")
    if meta.get("name"):
        print(f"Name        : {meta['name']}")
    if meta.get("category"):
        print(f"Category    : {meta['category']}")
    if meta.get("description"):
        print(f"Description : {meta['description']}")
    if meta.get("requirements"):
        print(f"Requirements: {meta['requirements']}")
    print(f"CID         : ipfs://{comp.cid}")
    print(f"Formation   : {comp.formation}")
    print(f"Organization: {comp.organization}")
    print(f"Prize Certificate Claim: {end_at_str} ({claim_ts})")
    print(f"Certificate : ipfs://{comp.certificateCID}")
    if meta.get("guideBookCID"):
        print(f"GuideBook   : ipfs://{meta['guideBookCID']}")

    meta_winners = meta.get("winners", [])

    print(f"\n{'='*50}")
    print("Winners")
    print(f"{'='*50}")
    winners_list = contract.getWinners(comp.id)
    if winners_list:
        for index, w in enumerate(winners_list):
            prize_eth = w.prizeAmount / 10**18
            token_label = "Native Token" if w.prizeToken == NATIVE_TOKEN else w.prizeToken
            w_title = meta_winners[index].get("title") if index < len(meta_winners) and isinstance(meta_winners[index], dict) else f"Winner #{w.id}"
            print(f"  [{index}] {w_title}")
            print(f"    Winner ID   : {w.id}")
            print(f"    Prize Token : {token_label}")
            print(f"    Prize Amount: {prize_eth} ({w.prizeAmount} wei)")
            print(f"    Certificate : ipfs://{w.certificateCID}")
    else:
        print("  No winners found.")


@click.command()
@click.argument("account_name")
@click.argument("competition_id", type=int, required=False, default=None)
@click.option("--organization", "-o", "org_address", default=None, help="Filter competitions by organization address")
@click.option("--all", "-a", "fetch_all", is_flag=True, default=False, help="Fetch all competitions")
@click.option("--contract", "contract_address", default=None, help="Contract address (default: COMPETITION_CONTRACT from .env)")
@click.option("--network", help="Network specifier")
def cli(account_name, competition_id, org_address, fetch_all, contract_address, network):
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

        if org_address:
            print(f"\nFetching competitions for organization {org_address}...")
            comps = contract.getCompetitionsByOrganization(org_address)
            if not comps:
                print(f"No competitions found for organization {org_address}.")
                return
            for comp in comps:
                display_competition(contract, comp)
        elif fetch_all or competition_id is None:
            print(f"\nFetching all competitions...")
            comps = contract.getAllCompetitions()
            if not comps:
                print("No competitions found.")
                return
            for comp in comps:
                display_competition(contract, comp)
        else:
            print(f"\nFetching competition ID {competition_id}...")
            comp = contract.getCompetition(competition_id)
            if comp.id == 0:
                print(f"Error: Competition ID {competition_id} does not exist.")
                return
            display_competition(contract, comp)

