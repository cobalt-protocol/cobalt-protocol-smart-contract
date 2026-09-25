import json
import os
from pathlib import Path

import click
import requests
from ape import accounts, networks, project
from dotenv import load_dotenv, set_key

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


def update_env(competition_address):
    env_path = str(Path(project.path) / ".env")

    set_key(env_path, "COMPETITION_CONTRACT", competition_address)
    set_key(env_path, "CERTIFICATE_COMPETITION_CONTRACT", competition_address)
    set_key(env_path, "TREASURY_PLATFORM_CONTRACT", competition_address)
    set_key(env_path, "LISTING_TOKEN_PRIZE_CONTRACT", competition_address)
    set_key(env_path, "PRICE_COMPETITION_MANAGER_CONTRACT", competition_address)
    set_key(env_path, "SIGNER_MANAGER_CONTRACT", competition_address)
    set_key(env_path, "SIGNER_MANAGER_CERTIFICATE_CONTRACT", competition_address)
    set_key(env_path, "CERTIFICATE_MANAGER_CONTRACT", competition_address)
    set_key(env_path, "TREASURY_PRIZE_CONTRACT", competition_address)

    print(f"\nUpdated .env:")
    print(f"  COMPETITION_CONTRACT={competition_address}")


@click.command()
@click.argument("platform_account_name")
@click.argument("signer_account_name")
@click.argument("organization_account_name")
@click.option("--signer", "signer_address", default=None, help="Signer address (default: PUBLIC_KEY_SIGNER from .env or signer_account address)")
@click.option("--fee", "fee_amount", default=0.5, type=float, help="Platform fee amount in token unit (default: 0.5)")
@click.option("--usdt", "usdt_address", default=USDT_TOKEN, help=f"USDT token address (default: {USDT_TOKEN})")
@click.option("--auto-listing/--no-auto-listing", default=True, help="Auto listing tokens and setting platform fee (default: yes)")
@click.option("--network", help="Network specifier")
def cli(platform_account_name, signer_account_name, organization_account_name, signer_address, fee_amount, usdt_address, auto_listing, network):
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

        try:
            account_signer = accounts.load(signer_account_name)
            try:
                account_signer.set_autosign(True, passphrase="")
            except Exception:
                pass
        except KeyError:
            print(f"Error: Signer account '{signer_account_name}' is not found in Ape.")
            return

        try:
            account_org = accounts.load(organization_account_name)
            try:
                account_org.set_autosign(True, passphrase="")
            except Exception:
                pass
        except KeyError:
            print(f"Error: Organization account '{organization_account_name}' is not found in Ape.")
            return

        signer_address = signer_address or os.getenv("PUBLIC_KEY_SIGNER") or account_signer.address

        token_symbol = provider.network.ecosystem.fee_token_symbol

        print(f"Platform Account    : {account_platform.address}")
        print(f"Signer Account      : {account_signer.address}")
        print(f"Organization Account: {account_org.address}")
        print(f"Signer Address      : {signer_address}")

        print("\nDeploying CompetitionManager...")
        competition_contract = project.CompetitionManager.deploy(
            account_platform.address,
            signer_address,
            sender=account_platform,
        )

        competition_address = competition_contract.address

        if auto_listing:
            print("\n--- Auto Setup: Token Listing & Fee Setup ---")

            # 1. Add Native Token (BOT / 0x0000...0000) to ListingTokenPrize
            if not competition_contract.isTokenListed(NATIVE_TOKEN):
                print(f"Adding Native Token ({NATIVE_TOKEN}) to ListingTokenPrize...")
                competition_contract.addListingTokenPrize(NATIVE_TOKEN, sender=account_platform)
            else:
                print(f"Native Token ({NATIVE_TOKEN}) is already listed.")

            # 2. Add USDT Token (0x75ed...0fe3) to ListingTokenPrize
            if not competition_contract.isTokenListed(usdt_address):
                print(f"Adding USDT Token ({usdt_address}) to ListingTokenPrize...")
                competition_contract.addListingTokenPrize(usdt_address, sender=account_platform)
            else:
                print(f"USDT Token ({usdt_address}) is already listed.")

            # 3. Set Platform Fee (default: 0.5 BOT / 500000000000000000 wei)
            treasury_fee_wei = int(fee_amount * 10**18)
            fee_metadata = {
                "name": f"Platform Fee Tier ({fee_amount} {token_symbol})",
                "description": f"Standard platform fee of {fee_amount} {token_symbol} for creating competitions",
                "treasuryFee": treasury_fee_wei,
                "tokenAddress": NATIVE_TOKEN,
            }
            print("\nUploading fee metadata to Kubo IPFS...")
            cid = upload_to_kubo_ipfs(fee_metadata) or "QmDefaultFeeCID"
            print(f"Fee Metadata CID: {cid}")

            print(f"Setting platform fee option #{1} ({fee_amount} {token_symbol})...")
            competition_contract.setPriceCompetitionFee(treasury_fee_wei, NATIVE_TOKEN, cid, sender=account_platform)
        else:
            print("\nSkipping auto listing and fee setup (use --auto-listing to enable)")

        print(f"\nCompetitionManager          : {competition_address}")
        print("Deploy success!")

        update_env(str(competition_address))


