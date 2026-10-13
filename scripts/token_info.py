import click

from decimal import Decimal
from ape import Contract, accounts, networks

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"

ERC20_ABI = [
    {
        "type": "function",
        "name": "balanceOf",
        "stateMutability": "view",
        "inputs": [{"name": "_owner", "type": "address"}],
        "outputs": [{"name": "", "type": "uint256"}],
    },
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
@click.argument("account_name")
@click.option(
    "--token",
    default=NATIVE_TOKEN,
    show_default=True,
    help="ERC-20 token address. Use zero address for native token.",
)
@click.option(
    "--network",
    default=None,
    help="Ape network specifier, e.g. ethereum:mainnet:node.",
)
def cli(account_name, token, network):
    try:
        with networks.parse_network_choice(network) as provider:
            print(f"Active Network: {provider.network.name}")

            try:
                account = accounts.load(account_name)
            except KeyError:
                raise click.ClickException(
                    f"Account '{account_name}' was not found in Ape."
                )

            print(f"Wallet Address: {account.address}")

            if token.lower() == NATIVE_TOKEN.lower():
                symbol = provider.network.ecosystem.fee_token_symbol
                raw_balance = account.balance
                decimals = 18

                balance = Decimal(raw_balance) / (Decimal(10) ** decimals)

                print(f"Token Type    : Native Token ({NATIVE_TOKEN})")
                print(f"Symbol        : {symbol}")
                print(f"Decimals      : {decimals}")
                print(
                    f"Balance       : {balance} {symbol} " f"({raw_balance} base units)"
                )
                return

            try:
                erc20 = Contract(address=token, abi=ERC20_ABI)
                raw_balance = erc20.balanceOf(account.address)

                try:
                    symbol = erc20.symbol()
                except Exception:
                    symbol = "UNKNOWN"

                try:
                    decimals = int(erc20.decimals())
                except Exception as exc:
                    raise click.ClickException(
                        f"Cannot read decimals() from token {token}: {exc}"
                    )

                balance = Decimal(raw_balance) / (Decimal(10) ** decimals)

                print(f"Token Type    : ERC-20 ({token})")
                print(f"Symbol        : {symbol}")
                print(f"Decimals      : {decimals}")
                print(
                    f"Balance       : {balance} {symbol} " f"({raw_balance} base units)"
                )

            except click.ClickException:
                raise
            except Exception as exc:
                raise click.ClickException(
                    f"Failed to fetch ERC-20 token {token}: {exc}"
                )

    except click.ClickException:
        raise
    except Exception as exc:
        raise click.ClickException(str(exc))


if __name__ == "__main__":
    cli()
