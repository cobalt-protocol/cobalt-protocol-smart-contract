import click
from ape import networks
from eth_account import Account
from web3 import Web3


@click.command()
@click.option("--network", default="bot_chain:bot_chain_test_net:node", help="Network specifier")
def cli(network):
    with networks.parse_network_choice(network) as provider:
        w3 = Web3(Web3.HTTPProvider(provider.http_uri))
        account = Account.create()
        balance = w3.eth.get_balance(account.address)

        print(f"Network     : {provider.network.ecosystem.name} - {provider.network.name} (Chain ID: {w3.eth.chain_id})")
        print(f"Address     : {account.address}")
        print(f"Private Key : {account.key.hex()}")
        print(f"Balance     : {w3.from_wei(balance, 'ether')} {provider.network.ecosystem.fee_token_symbol}")
