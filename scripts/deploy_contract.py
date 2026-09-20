import os
from pathlib import Path

import click
from ape import accounts, networks, project
from dotenv import load_dotenv, set_key

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


def update_env(certificate_competition_address, competition_address, treasury_address, listing_token_prize_address, fee_manager_address, signer_manager_address, signer_manager_certificate_address, certificate_manager_address):
    env_path = str(Path(project.path) / ".env")

    set_key(env_path, "CERTIFICATE_COMPETITION_CONTRACT", certificate_competition_address)
    set_key(env_path, "COMPETITION_CONTRACT", competition_address)
    set_key(env_path, "TREASURY_PLATFORM_CONTRACT", treasury_address)
    set_key(env_path, "LISTING_TOKEN_PRIZE_CONTRACT", listing_token_prize_address)
    set_key(env_path, "FEE_MANAGER_CONTRACT", fee_manager_address)
    set_key(env_path, "SIGNER_MANAGER_CONTRACT", signer_manager_address)
    set_key(env_path, "SIGNER_MANAGER_CERTIFICATE_CONTRACT", signer_manager_certificate_address)
    set_key(env_path, "CERTIFICATE_MANAGER_CONTRACT", certificate_manager_address)

    print(f"\nUpdated .env:")
    print(f"  CERTIFICATE_COMPETITION_CONTRACT={certificate_competition_address}")
    print(f"  COMPETITION_CONTRACT={competition_address}")
    print(f"  TREASURY_PLATFORM_CONTRACT={treasury_address}")
    print(f"  LISTING_TOKEN_PRIZE_CONTRACT={listing_token_prize_address}")
    print(f"  FEE_MANAGER_CONTRACT={fee_manager_address}")
    print(f"  SIGNER_MANAGER_CONTRACT={signer_manager_address}")
    print(f"  SIGNER_MANAGER_CERTIFICATE_CONTRACT={signer_manager_certificate_address}")
    print(f"  CERTIFICATE_MANAGER_CONTRACT={certificate_manager_address}")


@click.command()
@click.argument("account_name")
@click.option("--signer", "signer_address", default=None, help="Signer address (default: PUBLIC_KEY_SIGNER from .env or account_name address)")
@click.option("--network", help="Network specifier")
def cli(account_name, signer_address, network):
    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            akun = accounts.load(account_name)
            try:
                akun.set_autosign(True, passphrase="")
            except Exception:
                pass
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        signer_address = signer_address or os.getenv("PUBLIC_KEY_SIGNER") or akun.address

        token_symbol = provider.network.ecosystem.fee_token_symbol
        saldo_eth = akun.balance / 10**18

        print(f"Deployer    : {akun.address}")
        print(f"Signer      : {signer_address}")
        print(f"Balance     : {saldo_eth} {token_symbol}")

        print("\nDeploying CertificateCompetition...")
        certificate_competition_contract = project.CertificateCompetition.deploy(
            akun.address, signer_address, sender=akun
        )
        signer_manager_address = certificate_competition_contract.signerManagerContract()
        signer_manager_certificate_address = certificate_competition_contract.signerManagerCertificateContract()
        competition_address = certificate_competition_contract.competitionManagerContract()
        certificate_manager_address = certificate_competition_contract.certificateManagerContract()

        competition_contract = project.CompetitionManager.at(competition_address)
        treasury_address = competition_contract.treasuryPlatformContract()
        listing_token_prize_address = competition_contract.listingTokenPrizeContract()
        fee_manager_address = competition_contract.feeManagerContract()

        print("\nAdding native token to ListingTokenPrize...")
        listing_token_contract = project.ListingTokenPrizeContract.at(listing_token_prize_address)
        listing_token_contract.addListingTokenPrize(NATIVE_TOKEN, sender=akun)

        print("Setting default platform fee (ID #1) on FeeManager...")
        fee_manager_contract_inst = project.FeeManager.at(fee_manager_address)
        fee_manager_contract_inst.setFees(0, "Free Tier", "Default free tier fee", sender=akun)

        print(f"\nCertificateCompetition      : {certificate_competition_contract.address}")
        print(f"SignerManager               : {signer_manager_address}")
        print(f"SignerManagerCertificate     : {signer_manager_certificate_address}")
        print(f"CompetitionManager          : {competition_address}")
        print(f"CertificateManager          : {certificate_manager_address}")
        print(f"TreasuryPlatform            : {treasury_address}")
        print(f"ListingTokenPrize           : {listing_token_prize_address}")
        print(f"FeeManager                  : {fee_manager_address}")
        print("Deploy success!")

        update_env(
            str(certificate_competition_contract.address),
            str(competition_address),
            str(treasury_address),
            str(listing_token_prize_address),
            str(fee_manager_address),
            str(signer_manager_address),
            str(signer_manager_certificate_address),
            str(certificate_manager_address),
        )


