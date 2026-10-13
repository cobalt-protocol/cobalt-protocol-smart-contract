import click

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
    help="Token address. Use zero address to represent native token.",
)
@click.option(
    "--network",
    default=None,
    help="Ape network specifier, e.g. ethereum:mainnet:node.",
)
def cli(token, network):
    try:
        with networks.parse_network_choice(network) as provider:
            print(f"Active Network: {provider.network.name}")
            print(f"Chain ID      : {provider.chain_id}")
            print(f"Token Address : {token}")

            # Native token marker
            if token.lower() == NATIVE_TOKEN.lower():
                symbol = provider.network.ecosystem.fee_token_symbol

                print("Token Type    : Native Token")
                print(f"Symbol        : {symbol}")
                print("Decimals      : 18")
                return

            # Check whether address contains contract bytecode
            code = provider.get_code(token)

            if not code or code in ("0x", b""):
                print("Token Type    : Unknown / EOA")
                print("Result        : No contract code at this address")
                return

            # Probe ERC-20 metadata methods
            contract = Contract(address=token, abi=ERC20_ABI)

            try:
                symbol = contract.symbol()
                decimals = int(contract.decimals())

                if not 0 <= decimals <= 255:
                    raise ValueError("Decimals outside uint8 range")

                print("Token Type    : ERC-20 compatible")
                print(f"Symbol        : {symbol}")
                print(f"Decimals      : {decimals}")

            except Exception:
                print("Token Type    : Contract, not verified as ERC-20")
                print("Result        : Could not read standard ERC-20 metadata")

    except Exception as exc:
        raise click.ClickException(str(exc))


if __name__ == "__main__":
    cli()
