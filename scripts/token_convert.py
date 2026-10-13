import click

from decimal import Decimal
from ape import Contract, networks

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"

ERC20_ABI = [
    {
        "type": "function",
        "name": "symbol",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [{"name": "", "type": "string"}],
    },
    {
        "type": "function",
        "name": "decimals",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint8"}],
    },
]


@click.command()
@click.option(
    "--token",
    required=True,
    help="Token contract address. Use zero address for native token.",
)
@click.option(
    "--amount",
    required=True,
    type=str,
    help="Amount in smallest token units (integer).",
)
@click.option(
    "--network",
    default=None,
    help="Ape network specifier, e.g. ethereum:mainnet:node.",
)
def cli(token, amount, network):
    try:
        raw_amount = int(amount)

        if raw_amount < 0:
            raise click.ClickException("Amount cannot be negative.")

    except ValueError:
        raise click.ClickException(
            "Amount must be a non-negative integer in smallest units."
        )

    try:
        with networks.parse_network_choice(network) as provider:
            print(f"Active Network: {provider.network.name}")

            if token.lower() == NATIVE_TOKEN.lower():
                symbol = provider.network.ecosystem.fee_token_symbol
                decimals = 18
                token_type = "Native Token"

            else:
                contract = Contract(address=token, abi=ERC20_ABI)

                try:
                    symbol = contract.symbol()
                except Exception:
                    symbol = "UNKNOWN"

                try:
                    decimals = int(contract.decimals())
                except Exception as exc:
                    raise click.ClickException(
                        f"Cannot read decimals from token {token}: {exc}"
                    )

                if not 0 <= decimals <= 255:
                    raise click.ClickException(f"Invalid token decimals: {decimals}")

                token_type = "ERC-20 Token"

            converted_amount = Decimal(raw_amount) / (Decimal(10) ** decimals)

            print(f"Token Type    : {token_type}")
            print(f"Token Address : {token}")
            print(f"Symbol        : {symbol}")
            print(f"Decimals      : {decimals}")
            print(f"Raw Amount    : {raw_amount}")
            print(f"Converted     : {converted_amount} {symbol}")

    except click.ClickException:
        raise
    except Exception as exc:
        raise click.ClickException(str(exc))


if __name__ == "__main__":
    cli()
