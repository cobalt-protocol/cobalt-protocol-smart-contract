import click
from ape import accounts, networks, project


@click.command()
@click.argument("account_name")
@click.option("--network", help="Network specifier")
def cli(account_name, network):
    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            akun = accounts.load(account_name)
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        token_symbol = provider.network.ecosystem.fee_token_symbol
        saldo_eth = akun.balance / 10**18

        print(f"Deployer    : {akun.address}")
        print(f"Balance     : {saldo_eth} {token_symbol}")

        print("Deploying EventCompetition...")
        contract = project.EventCompetition.deploy(sender=akun)

        print(f"Contract    : {contract.address}")
        print("Deploy success!")
