import os

import click
from ape import accounts, networks, project
from dotenv import load_dotenv

load_dotenv()


@click.command()
@click.argument("account_name")
@click.argument("new_signer_address")
@click.option(
    "--target",
    type=click.Choice(["mint", "cert", "both"], case_sensitive=False),
    default="both",
    help="Target SignerManager instance: 'mint', 'cert', or 'both' (default: both)",
)
@click.option(
    "--contract",
    "contract_address",
    default=None,
    help="Contract address (default: CERTIFICATE_COMPETITION_CONTRACT from .env)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, new_signer_address, target, contract_address, network):
    contract_address = contract_address or os.getenv("CERTIFICATE_COMPETITION_CONTRACT")
    if not contract_address:
        print(
            "Error: Contract address not provided and CERTIFICATE_COMPETITION_CONTRACT not set in .env"
        )
        return

    target = target.lower()

    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            owner_account = accounts.load(account_name)
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        token_symbol = provider.network.ecosystem.fee_token_symbol
        saldo_eth = owner_account.balance / 10**18

        print(f"Caller             : {owner_account.address}")
        print(f"Balance            : {saldo_eth} {token_symbol}")
        print(f"New Signer Target  : {new_signer_address}")
        print(f"Target Instance    : {target}")

        contract = project.CertificateCompetition.at(contract_address)

        if target in ("mint", "both"):
            signer_manager_address = contract.signerManagerContract()
            signer_manager = project.SignerManager.at(signer_manager_address)
            old_signer = signer_manager.signerAddress()
            print(f"\n[SignerManager (Mint NFT)]")
            print(f"Address        : {signer_manager.address}")
            print(f"Current Signer : {old_signer}")
            if old_signer.lower() == new_signer_address.lower():
                print("Signer address is already set to the new address.")
            else:
                print("Updating signer address on SignerManager...")
                tx = signer_manager.setSignerAddress(new_signer_address, sender=owner_account)
                print(f"TX Hash        : {tx.txn_hash}")
                print(f"Updated Signer : {signer_manager.signerAddress()}")

        if target in ("cert", "both"):
            signer_manager_cert_address = contract.signerManagerCertificateContract()
            signer_manager_cert = project.SignerManager.at(signer_manager_cert_address)
            old_signer_cert = signer_manager_cert.signerAddress()
            print(f"\n[SignerManagerCertificate (Data Storage)]")
            print(f"Address        : {signer_manager_cert.address}")
            print(f"Current Signer : {old_signer_cert}")
            if old_signer_cert.lower() == new_signer_address.lower():
                print("Signer address is already set to the new address.")
            else:
                print("Updating signer address on SignerManagerCertificate...")
                tx = signer_manager_cert.setSignerAddress(new_signer_address, sender=owner_account)
                print(f"TX Hash        : {tx.txn_hash}")
                print(f"Updated Signer : {signer_manager_cert.signerAddress()}")

        print("\nSigner address update task finished!")
