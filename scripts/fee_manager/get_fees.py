#!/usr/bin/env python3
import os

import click
import requests
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


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


@click.command()
@click.argument("account_name")
@click.option("--fee-id", "platform_fee_id", default=1, type=int, help="Platform fee ID (default: 1)")
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, platform_fee_id, contract_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT") or os.getenv("PRICE_COMPETITION_MANAGER_CONTRACT") or os.getenv("PRIZE_COMPETITION_MANAGER_CONTRACT") or os.getenv("FEE_MANAGER_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and COMPETITION_CONTRACT not set in .env"
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

        contract = project.CompetitionManager.at(contract_address)
        print(f"Contract    : {contract.address}")

        fee = contract.getPriceCompetitionFee(platform_fee_id)
        if fee.id == 0:
            print(f"\nFee Option ID #{platform_fee_id} does not exist.")
            return

        meta = fetch_from_kubo_ipfs(fee.cid) if hasattr(fee, "cid") and fee.cid else {}

        print(f"\n{'='*50}")
        print(f"Fee Option #{fee.id}")
        print(f"{'='*50}")
        if meta.get("name"):
            print(f"  Name         : {meta['name']}")
        if meta.get("description"):
            print(f"  Description  : {meta['description']}")
        print(f"  CID          : ipfs://{fee.cid}")
        print(f"  Token Address: {fee.tokenAddress}")
        print(f"  Treasury Fee : {fee.treasuryFee / 10**18} {token_symbol} ({fee.treasuryFee} wei)")


