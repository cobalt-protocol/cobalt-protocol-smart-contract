import os
from pathlib import Path

import click
import requests
from ape import accounts, networks, project
from dotenv import load_dotenv, set_key
from eth_abi import encode

load_dotenv()


DEFAULT_RPC_URL = "https://rpc.botchain.ai"


def get_rpc_url() -> str:
    """
    Get the RPC URL from the active provider if available,
    otherwise fallback to default mainnet RPC.
    """
    if networks.active_provider and getattr(networks.active_provider, "uri", None):
        return networks.active_provider.uri
    return DEFAULT_RPC_URL


def update_env(competition_address: str):
    env_path = str(Path(project.path) / ".env")

    set_key(
        env_path,
        "COMPETITION_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "CERTIFICATE_COMPETITION_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "TREASURY_PLATFORM_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "LISTING_TOKEN_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "PRICE_COMPETITION_MANAGER_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "SIGNER_MANAGER_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "SIGNER_MANAGER_CERTIFICATE_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "CERTIFICATE_MANAGER_CONTRACT",
        competition_address,
    )

    set_key(
        env_path,
        "TREASURY_PRIZE_CONTRACT",
        competition_address,
    )

    print("\nUpdated .env:")
    print(f"  COMPETITION_CONTRACT=" f"{competition_address}")


def rpc_request(
    method: str,
    params: list,
):
    """
    Send JSON-RPC request directly to BOT Chain using the active provider's RPC URL.
    """

    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1,
    }

    response = requests.post(
        get_rpc_url(),
        json=payload,
        timeout=30,
    )

    response.raise_for_status()

    result = response.json()

    if "error" in result:
        raise RuntimeError(result["error"])

    if "result" not in result:
        raise RuntimeError(f"Unexpected RPC response: {result}")

    return result["result"]


def get_gas_price() -> int:
    """
    Get current gas price from BOT Chain RPC.
    """

    result = rpc_request(
        "eth_gasPrice",
        [],
    )

    return int(
        result,
        16,
    )


def get_native_balance(
    address: str,
) -> int:
    """
    Get native token balance from BOT Chain RPC.
    """

    result = rpc_request(
        "eth_getBalance",
        [
            address,
            "latest",
        ],
    )

    return int(
        result,
        16,
    )


def get_deployment_bytecode(
    contract,
) -> str:
    """
    Get contract creation/deployment bytecode.
    """

    bytecode = contract.contract_type.deployment_bytecode.bytecode

    if not bytecode:
        raise ValueError("CompetitionManager deployment " "bytecode is empty.")

    # Ensure bytecode starts with 0x
    if not bytecode.startswith("0x"):
        bytecode = "0x" + bytecode

    return bytecode


def build_deployment_data(
    contract,
    platform_address: str,
    signer_address: str,
) -> str:
    """
    Build:

        deployment bytecode
        +
        ABI encoded constructor arguments

    CompetitionManager constructor:

        constructor(
            address platform,
            address signer
        )
    """

    bytecode = get_deployment_bytecode(contract)

    # Constructor:
    #
    # address platform
    # address signer
    #
    encoded_arguments = encode(
        [
            "address",
            "address",
        ],
        [
            platform_address,
            signer_address,
        ],
    )

    encoded_arguments_hex = encoded_arguments.hex()

    return bytecode + encoded_arguments_hex


def estimate_deployment_gas(
    contract,
    platform_address: str,
    signer_address: str,
) -> int:
    """
    Estimate deployment gas using:

        eth_estimateGas

    directly against BOT Chain RPC.
    """

    deployment_data = build_deployment_data(
        contract=contract,
        platform_address=platform_address,
        signer_address=signer_address,
    )

    transaction = {
        "from": platform_address,
        "data": deployment_data,
    }

    print("\nCalling BOT Chain " "eth_estimateGas...")

    result = rpc_request(
        "eth_estimateGas",
        [
            transaction,
        ],
    )

    return int(
        result,
        16,
    )


def wei_to_bot(
    value: int,
) -> float:
    """
    Convert Wei to BOT.

    Assumes 18 decimals.
    """

    return value / 10**18


def wei_to_gwei(
    value: int,
) -> float:
    """
    Convert Wei to Gwei.
    """

    return value / 10**9


@click.command()
@click.argument("platform_account_name")
@click.argument("signer_account_name")
@click.argument("organization_account_name")
@click.option(
    "--signer",
    "signer_address",
    default=None,
    help=(
        "Signer address "
        "(default: PUBLIC_KEY_SIGNER from .env "
        "or signer account address)"
    ),
)
@click.option(
    "--network",
    help="Network specifier",
)
def cli(
    platform_account_name,
    signer_account_name,
    organization_account_name,
    signer_address,
    network,
):
    # ==========================================================
    # NETWORK
    # ==========================================================

    with networks.parse_network_choice(network) as provider:

        print(f"Active Network: " f"{provider.network.name}")

        print(f"Provider      : " f"{provider.name}")

        # ======================================================
        # PLATFORM ACCOUNT
        # ======================================================

        try:
            account_platform = accounts.load(platform_account_name)

            try:
                account_platform.set_autosign(
                    True,
                    passphrase="",
                )
            except Exception:
                pass

        except KeyError:
            print(
                f"Error: Platform account "
                f"'{platform_account_name}' "
                f"is not found in Ape."
            )
            return

        # ======================================================
        # SIGNER ACCOUNT
        # ======================================================

        try:
            account_signer = accounts.load(signer_account_name)

            try:
                account_signer.set_autosign(
                    True,
                    passphrase="",
                )
            except Exception:
                pass

        except KeyError:
            print(
                f"Error: Signer account "
                f"'{signer_account_name}' "
                f"is not found in Ape."
            )
            return

        # ======================================================
        # ORGANIZATION ACCOUNT
        # ======================================================

        try:
            account_org = accounts.load(organization_account_name)

            try:
                account_org.set_autosign(
                    True,
                    passphrase="",
                )
            except Exception:
                pass

        except KeyError:
            print(
                f"Error: Organization account "
                f"'{organization_account_name}' "
                f"is not found in Ape."
            )
            return

        # ======================================================
        # SIGNER ADDRESS
        # ======================================================

        signer_address = (
            signer_address or os.getenv("PUBLIC_KEY_SIGNER") or account_signer.address
        )

        # ======================================================
        # ACCOUNT INFORMATION
        # ======================================================

        print()

        print(f"Platform Account    : " f"{account_platform.address}")

        print(f"Signer Account      : " f"{account_signer.address}")

        print(f"Organization Account: " f"{account_org.address}")

        print(f"Signer Address      : " f"{signer_address}")

        # ======================================================
        # BALANCE
        # ======================================================

        print()
        print("Checking platform " "account balance...")

        try:
            balance = get_native_balance(account_platform.address)

        except Exception as exc:
            print()
            print("Unable to get platform balance:")
            print(f"  {exc}")
            return

        print()
        print("Platform Balance")
        print("----------------------------------------")
        print(f"Balance Wei : " f"{balance:,}")
        print(f"Balance BOT : " f"{wei_to_bot(balance):.12f}")

        # ======================================================
        # CONTRACT
        # ======================================================

        contract = project.CompetitionManager

        # ======================================================
        # ESTIMATE GAS
        # ======================================================

        print()
        print("Estimating CompetitionManager " "deployment gas...")

        try:
            gas_estimate = estimate_deployment_gas(
                contract=contract,
                platform_address=(account_platform.address),
                signer_address=signer_address,
            )

        except Exception as exc:
            print()
            print("Gas estimation failed:")
            print(f"  {exc}")
            print()
            print("Deployment has been cancelled.")
            return

        # ======================================================
        # GAS PRICE
        # ======================================================

        print()
        print("Getting current gas price...")

        try:
            gas_price = get_gas_price()

        except Exception as exc:
            print()
            print("Unable to get gas price:")
            print(f"  {exc}")
            print()
            print("Deployment has been cancelled.")
            return

        # ======================================================
        # ESTIMATED FEE
        # ======================================================

        estimated_fee_wei = gas_estimate * gas_price

        estimated_fee_bot = wei_to_bot(estimated_fee_wei)

        gas_price_gwei = wei_to_gwei(gas_price)

        # ======================================================
        # DISPLAY ESTIMATION
        # ======================================================

        print()
        print("========================================")
        print("Deployment Gas Estimation")
        print("========================================")

        print(f"Estimated Gas     : " f"{gas_estimate:,}")

        print(f"Gas Price         : " f"{gas_price_gwei:.6f} Gwei")

        print(f"Estimated Fee     : " f"{estimated_fee_bot:.12f} BOT")

        print(f"Estimated Fee Wei : " f"{estimated_fee_wei:,}")

        # ======================================================
        # BALANCE CHECK
        # ======================================================

        remaining_balance = balance - estimated_fee_wei

        print()
        print("Balance Check")
        print("----------------------------------------")

        print(f"Current Balance   : " f"{wei_to_bot(balance):.12f} BOT")

        print(f"Estimated Fee     : " f"{estimated_fee_bot:.12f} BOT")

        if remaining_balance >= 0:

            print(f"Remaining Balance : " f"{wei_to_bot(remaining_balance):.12f} BOT")

        else:

            print(
                f"Shortfall         : " f"{wei_to_bot(abs(remaining_balance)):.12f} BOT"
            )

        # ======================================================
        # INSUFFICIENT BALANCE
        # ======================================================

        if balance < estimated_fee_wei:

            print()
            print("WARNING:")

            print("Insufficient balance " "for deployment.")

            print()
            print("Deployment has been cancelled.")

            return

        # ======================================================
        # CONFIRM DEPLOYMENT
        # ======================================================

        print()
        print("The contract has NOT been " "deployed yet.")

        print(f"Maximum estimated deployment " f"cost: {estimated_fee_bot:.12f} BOT")

        if not click.confirm("\nDo you want to continue " "with deployment?"):
            print("\nDeployment cancelled.")
            return

        # ======================================================
        # DEPLOY
        # ======================================================

        print()
        print("Deploying CompetitionManager...")

        try:
            competition_contract = contract.deploy(
                account_platform.address,
                signer_address,
                sender=account_platform,
            )

        except Exception as exc:
            print()
            print("Deployment failed:")
            print(f"  {exc}")
            return

        # ======================================================
        # CONTRACT ADDRESS
        # ======================================================

        competition_address = competition_contract.address

        print()
        print("========================================")
        print("Deployment Successful")
        print("========================================")

        print(f"CompetitionManager : " f"{competition_address}")

        # ======================================================
        # ACTUAL RECEIPT
        # ======================================================

        try:
            receipt = competition_contract.creation_metadata.receipt

            print()
            print("Actual Transaction")

            print("----------------------------------------")

            print(f"Transaction Hash : " f"{receipt.txn_hash}")

            print(f"Gas Used         : " f"{receipt.gas_used:,}")

            try:
                actual_gas_price = receipt.gas_price

                actual_fee_wei = receipt.gas_used * actual_gas_price

                actual_fee_bot = wei_to_bot(actual_fee_wei)

                print(
                    f"Actual Gas Price : " f"{wei_to_gwei(actual_gas_price):.6f} Gwei"
                )

                print(f"Actual Gas Fee   : " f"{actual_fee_bot:.12f} BOT")

                print(f"Actual Fee Wei   : " f"{actual_fee_wei:,}")

            except Exception as exc:
                print("Warning: Unable to " "calculate actual gas fee:")
                print(f"  {exc}")

        except Exception as exc:
            print()
            print("Warning: Unable to retrieve " "deployment receipt:")
            print(f"  {exc}")

        # ======================================================
        # UPDATE ENV
        # ======================================================

        update_env(str(competition_address))

        print()
        print("Deploy success!")


if __name__ == "__main__":
    cli()
