import json
import os

import click
import requests
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"
USDT_TOKEN = "0x75edC9335175Fc0552D51D48439F229c10420fe3"


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
@click.argument("platform_account_name")
@click.option("--contract", "contract_address", default=None, help="Contract address (default: COMPETITION_CONTRACT from .env)")
@click.option("--fee", "fee_amount", default=0.5, type=float, help="Platform fee amount in token unit (default: 0.5)")
@click.option("--usdt", "usdt_address", default=USDT_TOKEN, help=f"USDT token address (default: {USDT_TOKEN})")
@click.option("--network", help="Network specifier")
def cli(platform_account_name, contract_address, fee_amount, usdt_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT")
    if not contract_address:
        print("Error: Contract address not provided and COMPETITION_CONTRACT not set in .env")
        return

    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            account_platform = accounts.load(platform_account_name)
            try:
                account_platform.set_autosign(True, passphrase="")
            except Exception:
                pass
        except KeyError:
            print(f"Error: Platform account '{platform_account_name}' is not found in Ape.")
            return

        token_symbol = provider.network.ecosystem.fee_token_symbol
        contract = project.CompetitionManager.at(contract_address)

        print(f"Platform Account: {account_platform.address}")
        print(f"Contract        : {contract.address}")

        print("\n--- Command 1: Setting Platform Fee (0.5 BOT) ---")
        treasury_fee_wei = int(fee_amount * 10**18)
        fee_metadata = {
            "name": f"Platform Fee Tier ({fee_amount} {token_symbol})",
            "description": f"Standard platform fee of {fee_amount} {token_symbol} for creating competitions",
            "treasuryFee": treasury_fee_wei,
            "tokenAddress": NATIVE_TOKEN,
        }
        print("Uploading fee metadata to Kubo IPFS...")
        cid = upload_to_kubo_ipfs(fee_metadata) or "QmDefaultFeeCID"
        print(f"Fee Metadata CID: {cid}")

        print(f"Setting platform fee ({fee_amount} {token_symbol})...")
        tx1 = contract.setPriceCompetitionFee(treasury_fee_wei, NATIVE_TOKEN, cid, sender=account_platform)
        print(f"Fee TX Hash     : {tx1.txn_hash}")

        print("\n--- Command 2: Adding Native Token to ListingTokenPrize ---")
        if not contract.isTokenListed(NATIVE_TOKEN):
            print(f"Adding Native Token ({NATIVE_TOKEN})...")
            tx2 = contract.addListingTokenPrize(NATIVE_TOKEN, sender=account_platform)
            print(f"Native Token TX : {tx2.txn_hash}")
        else:
            print(f"Native Token ({NATIVE_TOKEN}) is already listed.")

        print("\n--- Command 3: Adding USDT Token to ListingTokenPrize ---")
        if not contract.isTokenListed(usdt_address):
            print(f"Adding USDT Token ({usdt_address})...")
            tx3 = contract.addListingTokenPrize(usdt_address, sender=account_platform)
            print(f"USDT Token TX   : {tx3.txn_hash}")
        else:
            print(f"USDT Token ({usdt_address}) is already listed.")

        print("\nAll 3 setup commands executed successfully!")
