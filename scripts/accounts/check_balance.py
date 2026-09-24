import click
from ape import Contract, accounts, networks

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"

ERC20_ABI = [
    {
        "constant": True,
        "inputs": [{"name": "_owner", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "", "type": "uint256"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "symbol",
        "outputs": [{"name": "", "type": "string"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
]


@click.command()
@click.argument("account_name")
@click.option(
    "--token",
    default=NATIVE_TOKEN,
    help="Token address (default: 0x0000000000000000000000000000000000000000 for Native Token)",
)
@click.option("--network", help="Network specifier")
def cli(account_name, token, network):
    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            akun = accounts.load(account_name)
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        print(f"Wallet Address: {akun.address}")

        if not token or token == NATIVE_TOKEN:
            token_symbol = provider.network.ecosystem.fee_token_symbol
            saldo_eth = akun.balance / 10**18
            print(f"Token Type    : Native Token ({NATIVE_TOKEN})")
            print(f"Balance       : {saldo_eth} {token_symbol} ({akun.balance} wei)")
        else:
            try:
                erc20 = Contract(token, abi=ERC20_ABI)
                raw_balance = erc20.balanceOf(akun.address)

                try:
                    symbol = erc20.symbol()
                except Exception:
                    symbol = "ERC20"

                try:
                    decimals = erc20.decimals()
                except Exception:
                    decimals = 18

                formatted_balance = raw_balance / (10**decimals)
                print(f"Token Type    : ERC20 Token ({token})")
                print(f"Balance       : {formatted_balance} {symbol} ({raw_balance} wei)")
            except Exception as e:
                print(f"Error fetching ERC20 balance for token '{token}': {e}")
