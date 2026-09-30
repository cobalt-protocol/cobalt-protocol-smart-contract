#!/usr/bin/env python3
import json
import os

import click
import requests
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


def upload_to_kubo_ipfs(data: dict, endpoint: str = None) -> str:
    if endpoint is None:
        base_url = os.getenv("KUBO_API_URL", "http://localhost:5001").rstrip("/")
        endpoint = f"{base_url}/api/v0/add"

    json_bytes = json.dumps(data, indent=2).encode("utf-8")
    files = {"file": ("fee_metadata.json", json_bytes, "application/json")}

    try:
        response = requests.post(endpoint, files=files, timeout=10)
        response.raise_for_status()
        result = response.json()
        cid = result.get("Hash")
        if cid:
            return cid
        raise ValueError(f"No Hash in Kubo response: {result}")
    except Exception as e:
        print(f"Warning: Failed to upload to Kubo IPFS ({endpoint}): {e}")
        return ""


@click.command()
@click.argument("account_name")
@click.argument("treasury_fee", type=str)
@click.option("--fee-id", "fee_id", default=None, type=int, help="PriceCompetitionFee ID to update (if omitted, creates a new fee option)")
@click.option("--token", "token_address", default=NATIVE_TOKEN, help="Fee token address (default: native token)")
@click.option("--cid", default=None, help="IPFS CID for fee metadata")
@click.option("--name", default=None, help="Fee tier name metadata")
@click.option("--description", default=None, help="Fee tier description metadata")
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: PRICE_COMPETITION_MANAGER_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, treasury_fee, fee_id, token_address, cid, name, description, contract_address, network):
    try:
        val = float(treasury_fee)
        if val < 10**9:
            treasury_fee_wei = int(val * 10**18)
        else:
            treasury_fee_wei = int(val)
    except ValueError:
        print(f"Error: Invalid fee value '{treasury_fee}'")
        return
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

        print(f"Caller           : {akun.address}")
        print(f"Balance          : {saldo_eth} {token_symbol}")

        contract = project.CompetitionManager.at(contract_address)
        print(f"Contract         : {contract.address}")
        print(f"Token Address    : {token_address}")

        if not cid:
            fee_metadata = {
                "name": name or f"Fee Tier ({treasury_fee_wei / 10**18} Fee)",
                "description": description or "Platform price competition fee tier",
                "treasuryFee": treasury_fee_wei,
                "tokenAddress": token_address,
            }
            print("\nUploading fee metadata to Kubo IPFS (http://localhost:5001/api/v0/add)...")
            cid = upload_to_kubo_ipfs(fee_metadata) or "QmDefaultFeeCID"

        print(f"CID              : {cid}")
        print(f"New Treasury Fee : {treasury_fee_wei / 10**18} ({treasury_fee_wei} wei)")

        if fee_id is not None:
            print(f"\nUpdating fee option #{fee_id} on CompetitionManager...")
            tx = contract.updatePriceCompetitionFee(fee_id, treasury_fee_wei, token_address, cid, sender=akun)
        else:
            print("\nAdding fee option on CompetitionManager...")
            tx = contract.setPriceCompetitionFee(treasury_fee_wei, token_address, cid, sender=akun)

        print(f"TX Hash          : {tx.txn_hash}")
        print("Set fees success!")




