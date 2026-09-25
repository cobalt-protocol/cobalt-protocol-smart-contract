import os
from pathlib import Path

import click
from ape import accounts, networks, project
from dotenv import load_dotenv, set_key

load_dotenv()


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
@click.option("--network", help="Network specifier")
def cli(platform_account_name, signer_account_name, organization_account_name, signer_address, network):
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

        print(f"\nCompetitionManager          : {competition_address}")
        print("Deploy success!")

        update_env(str(competition_address))


