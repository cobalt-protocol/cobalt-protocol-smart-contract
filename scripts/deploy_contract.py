import os
from pathlib import Path

import click
from ape import accounts, networks, project
from dotenv import load_dotenv, set_key

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


def update_env(certificate_competition_address, competition_address, treasury_address, listing_token_prize_address, price_competition_manager_address, signer_manager_address, signer_manager_certificate_address, certificate_manager_address, treasury_prize_address):
    env_path = str(Path(project.path) / ".env")

    set_key(env_path, "CERTIFICATE_COMPETITION_CONTRACT", certificate_competition_address)
    set_key(env_path, "COMPETITION_CONTRACT", competition_address)
    set_key(env_path, "TREASURY_PLATFORM_CONTRACT", treasury_address)
    set_key(env_path, "LISTING_TOKEN_PRIZE_CONTRACT", listing_token_prize_address)
    set_key(env_path, "PRICE_COMPETITION_MANAGER_CONTRACT", price_competition_manager_address)
    set_key(env_path, "SIGNER_MANAGER_CONTRACT", signer_manager_address)
    set_key(env_path, "SIGNER_MANAGER_CERTIFICATE_CONTRACT", signer_manager_certificate_address)
    set_key(env_path, "CERTIFICATE_MANAGER_CONTRACT", certificate_manager_address)
    set_key(env_path, "TREASURY_PRIZE_CONTRACT", treasury_prize_address)

    print(f"\nUpdated .env:")
    print(f"  CERTIFICATE_COMPETITION_CONTRACT={certificate_competition_address}")
    print(f"  COMPETITION_CONTRACT={competition_address}")
    print(f"  TREASURY_PLATFORM_CONTRACT={treasury_address}")
    print(f"  LISTING_TOKEN_PRIZE_CONTRACT={listing_token_prize_address}")
    print(f"  PRICE_COMPETITION_MANAGER_CONTRACT={price_competition_manager_address}")
    print(f"  SIGNER_MANAGER_CONTRACT={signer_manager_address}")
    print(f"  SIGNER_MANAGER_CERTIFICATE_CONTRACT={signer_manager_certificate_address}")
    print(f"  CERTIFICATE_MANAGER_CONTRACT={certificate_manager_address}")
    print(f"  TREASURY_PRIZE_CONTRACT={treasury_prize_address}")


@click.command()
@click.argument("platform_account_name")
@click.argument("signer_account_name")
@click.argument("organization_account_name")
@click.option("--signer", "signer_address", default=None, help="Signer address (default: PUBLIC_KEY_SIGNER from .env or signer_account address)")
@click.option("--auto-listing/--no-auto-listing", default=False, help="Auto listing native token and set default fee (default: no)")
@click.option("--network", help="Network specifier")
def cli(platform_account_name, signer_account_name, organization_account_name, signer_address, auto_listing, network):
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

        print("\nDeploying PriceCompetitionManager...")
        price_competition_manager_contract = project.PriceCompetitionManager.deploy(
            account_platform.address, sender=account_platform
        )

        print("Deploying TreasuryPlatform...")
        treasury_platform_contract = project.TreasuryPlatform.deploy(
            account_platform.address, sender=account_platform
        )

        print("Deploying TreasuryPrize...")
        treasury_prize_contract = project.TreasuryPrize.deploy(
            account_platform.address, sender=account_platform
        )

        print("Deploying ListingTokenPrizeContract...")
        listing_token_prize_contract = project.ListingTokenPrizeContract.deploy(
            account_platform.address, sender=account_platform
        )

        print("Deploying SignerManager (Mint)...")
        signer_manager_contract = project.SignerManager.deploy(
            account_signer.address, signer_address, sender=account_signer
        )

        print("Deploying SignerManager (Certificate)...")
        signer_manager_certificate_contract = project.SignerManager.deploy(
            account_signer.address, signer_address, sender=account_signer
        )

        print("Deploying CompetitionManager...")
        competition_contract = project.CompetitionManager.deploy(
            account_platform.address,
            price_competition_manager_contract.address,
            treasury_platform_contract.address,
            listing_token_prize_contract.address,
            treasury_prize_contract.address,
            sender=account_org,
        )

        print("Deploying CertificateManager...")
        certificate_manager_contract = project.CertificateManager.deploy(
            account_platform.address,
            competition_contract.address,
            signer_manager_certificate_contract.address,
            sender=account_platform,
        )

        print("Deploying CertificateCompetition...")
        certificate_competition_contract = project.CertificateCompetition.deploy(
            account_platform.address,
            signer_manager_contract.address,
            signer_manager_certificate_contract.address,
            competition_contract.address,
            certificate_manager_contract.address,
            sender=account_platform,
        )

        signer_manager_address = signer_manager_contract.address
        signer_manager_certificate_address = signer_manager_certificate_contract.address
        competition_address = competition_contract.address
        certificate_manager_address = certificate_manager_contract.address
        treasury_address = treasury_platform_contract.address
        treasury_prize_address = treasury_prize_contract.address
        listing_token_prize_address = listing_token_prize_contract.address
        price_competition_manager_address = price_competition_manager_contract.address

        if auto_listing:
            print("\nAdding native token to ListingTokenPrize...")
            listing_token_prize_contract.addListingTokenPrize(NATIVE_TOKEN, sender=account_platform)

            print("Setting default platform fee (ID #1) on PriceCompetitionManager...")
            price_competition_manager_contract.setPriceCompetitionFee(0, NATIVE_TOKEN, "Free Tier", "Default free tier fee", sender=account_platform)
        else:
            print("\nSkipping auto listing and default fee setup (use --auto-listing to enable)")

        print(f"\nCertificateCompetition      : {certificate_competition_contract.address}")
        print(f"SignerManager               : {signer_manager_address}")
        print(f"SignerManagerCertificate     : {signer_manager_certificate_address}")
        print(f"CompetitionManager          : {competition_address}")
        print(f"CertificateManager          : {certificate_manager_address}")
        print(f"TreasuryPlatform            : {treasury_address}")
        print(f"TreasuryPrize               : {treasury_prize_address}")
        print(f"ListingTokenPrize           : {listing_token_prize_address}")
        print(f"PriceCompetitionManager     : {price_competition_manager_address}")
        print("Deploy success!")

        update_env(
            str(certificate_competition_contract.address),
            str(competition_address),
            str(treasury_address),
            str(listing_token_prize_address),
            str(price_competition_manager_address),
            str(signer_manager_address),
            str(signer_manager_certificate_address),
            str(certificate_manager_address),
            str(treasury_prize_address),
        )


