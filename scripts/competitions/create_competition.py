import json
import os
from datetime import datetime, timezone, timedelta

import click
from ape import accounts, networks, project, Contract
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"

ERC20_ABI = [
    {
        "constant": True,
        "inputs": [
            {"name": "_owner", "type": "address"},
            {"name": "_spender", "type": "address"},
        ],
        "name": "allowance",
        "outputs": [{"name": "", "type": "uint256"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
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
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": False,
        "inputs": [
            {"name": "_spender", "type": "address"},
            {"name": "_value", "type": "uint256"},
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "payable": False,
        "stateMutability": "nonpayable",
        "type": "function",
    },
]


def get_token_decimals(token_address):
    if not token_address or token_address == NATIVE_TOKEN:
        return 18
    try:
        erc20 = Contract(token_address, abi=ERC20_ABI)
        return erc20.decimals()
    except Exception:
        return 18


@click.command()
@click.argument("account_name")
@click.argument("input_json", type=click.Path(exists=True))
@click.option("--contract", "contract_address", default=None, help="Contract address (default: COMPETITION_CONTRACT from .env)")
@click.option("--network", help="Network specifier")
def cli(account_name, input_json, contract_address, network):
    contract_address = contract_address or os.getenv("COMPETITION_CONTRACT")
    if not contract_address:
        print("Error: Contract address not provided and COMPETITION_CONTRACT not set in .env")
        return

    with networks.parse_network_choice(network) as provider:
        print(f"Active Network: {provider.network.name}")
        try:
            akun = accounts.load(account_name)
        except KeyError:
            print(f"Error: Account '{account_name}' is not found in Ape.")
            return

        token_symbol = provider.network.ecosystem.fee_token_symbol
        saldo_eth = akun.balance / 10**18

        print(f"Caller      : {akun.address}")
        print(f"Balance     : {saldo_eth} {token_symbol}")

        contract = project.CompetitionManager.at(contract_address)
        print(f"Contract    : {contract.address}")

        price_competition_manager_address = contract.priceCompetitionManagerContract()
        price_competition_manager = project.PriceCompetitionManager.at(price_competition_manager_address)
        print(f"Price Competition Manager : {price_competition_manager.address}")

        with open(input_json, "r") as f:
            data = json.load(f)

        competition = data["competition"]
        winners_data = data["winners"]
        platform_fee_id = competition.get("platformFeeId", 1)

        fee_data = price_competition_manager.getPriceCompetitionFee(platform_fee_id)
        if fee_data.id == 0:
            print(f"Error: Fee option ID {platform_fee_id} does not exist in PriceCompetitionManager.")
            return

        treasury_fee = fee_data.treasuryFee
        fee_token = fee_data.tokenAddress

        if not winners_data:
            print("Error: Competition must have at least one winner.")
            return

        first_prize_token = winners_data[0]["prizeToken"]
        for i, w in enumerate(winners_data):
            if w["prizeToken"] != first_prize_token:
                print(f"Error: Winner [{i}] prizeToken ({w['prizeToken']}) does not match first winner prizeToken ({first_prize_token}). All winners in a competition must use the same prize token.")
                return

        listing_token_prize_address = contract.listingTokenPrizeContract()
        listing_token_prize = project.ListingTokenPrizeContract.at(listing_token_prize_address)
        print(f"Listing Token Prize Contract : {listing_token_prize.address}")

        listed_token = listing_token_prize.listingToken(first_prize_token)
        if listed_token.id == 0:
            print(f"Error: Prize token ({first_prize_token}) is not listed in ListingTokenPrizeContract.")
            return
        if not listed_token.isActive:
            print(f"Error: Prize token ({first_prize_token}) is listed but deactivated in ListingTokenPrizeContract.")
            return

        if fee_token == NATIVE_TOKEN:
            print("Fee Token     : Native Token")
        else:
            print(f"Fee Token     : {fee_token}")

        print(f"Fee Option ID : {platform_fee_id} ({fee_data.title} - {fee_data.description})")
        print(f"Treasury Fee  : {treasury_fee / 10**18} ({treasury_fee} wei)")

        try:
            chain_now_ts = int(provider.chain.blocks.head.timestamp)
        except Exception:
            chain_now_ts = int(datetime.now(timezone.utc).timestamp())

        if "durationInSeconds" in competition:
            duration_seconds = competition["durationInSeconds"]
            if duration_seconds < 60:
                duration_seconds = 60
            duration_desc = f"{duration_seconds} seconds"
            end_at_ts = chain_now_ts + duration_seconds
        elif "durationInDays" in competition:
            duration_days = competition["durationInDays"]
            duration_desc = f"{duration_days} days"
            end_at_ts = chain_now_ts + (duration_days * 86400)
        else:
            duration_desc = "300 seconds"
            end_at_ts = chain_now_ts + 300

        if "schedule" in competition and isinstance(competition["schedule"], dict):
            sched = competition["schedule"]
            reg_window = sched.get("registrationWindow") or chain_now_ts
            comp_window = sched.get("competitionWindow") or chain_now_ts
            sub_deadline = sched.get("submissionDeadline") or end_at_ts
            judging = sched.get("judgingReview") or end_at_ts
            announcement = sched.get("resultAnnouncement") or end_at_ts
            prize_claim = sched.get("prizeCertificateClaim") or end_at_ts

            if prize_claim <= chain_now_ts:
                prize_claim = end_at_ts
                sub_deadline = end_at_ts
                judging = end_at_ts
                announcement = end_at_ts
                reg_window = chain_now_ts
                comp_window = chain_now_ts
        else:
            reg_window = chain_now_ts
            comp_window = chain_now_ts
            sub_deadline = end_at_ts
            judging = end_at_ts
            announcement = end_at_ts
            prize_claim = end_at_ts

        schedule_tuple = (
            reg_window,
            comp_window,
            sub_deadline,
            judging,
            announcement,
            prize_claim,
        )

        org_setting = competition.get("organization", NATIVE_TOKEN)
        effective_org = akun.address if not org_setting or org_setting == NATIVE_TOKEN else org_setting
        formation_input = competition.get("formation", "1-3 member")

        competition_input = (
            0,
            competition["name"],
            competition["category"],
            competition["description"],
            competition["requirements"],
            formation_input,
            org_setting,
            schedule_tuple,
            competition["certificateCID"],
            competition.get("guideBookCID", ""),
        )

        prize_token_decimals = get_token_decimals(first_prize_token)
        fee_token_decimals = get_token_decimals(fee_token)

        def parse_prize_wei(val, decimals=18):
            f_val = float(val)
            return int(f_val * 10**decimals) if f_val < 10**9 else int(f_val)

        winners_input = []
        for w in winners_data:
            prize_amount_wei = parse_prize_wei(w["prizeAmount"], prize_token_decimals)
            winners_input.append((
                0,
                0,
                w["title"],
                w["prizeToken"],
                prize_amount_wei,
                w["certificateCID"],
            ))

        claim_dt = datetime.fromtimestamp(prize_claim, tz=timezone.utc)

        print(f"\n{'='*50}")
        print("Competition Details")
        print(f"{'='*50}")
        print(f"Name        : {competition['name']}")
        print(f"Category    : {competition['category']}")
        print(f"Description : {competition['description']}")
        print(f"Requirements: {competition['requirements']}")
        print(f"Formation   : {formation_input}")
        print(f"Organization: {effective_org}")
        print(f"Duration    : {duration_desc}")
        print(f"Schedule    :")
        print(f"  Registration Window    : {reg_window}")
        print(f"  Competition Window     : {comp_window}")
        print(f"  Submission Deadline    : {sub_deadline}")
        print(f"  Judging Review         : {judging}")
        print(f"  Result Announcement    : {announcement}")
        print(f"  Prize Certificate Claim: {claim_dt.strftime('%Y-%m-%d %H:%M:%S UTC')} ({prize_claim})")
        print(f"Certificate : ipfs://{competition['certificateCID']}")
        if competition.get("guideBookCID"):
            print(f"Guidebook   : ipfs://{competition['guideBookCID']}")

        print(f"\n{'='*50}")
        print(f"Winners ({len(winners_data)} total)")
        print(f"{'='*50}")
        for i, w in enumerate(winners_data):
            prize_amount_wei = parse_prize_wei(w["prizeAmount"], prize_token_decimals)
            print(f"  [{i}] {w['title']}")
            print(f"    Prize Token : {'Native Token' if w['prizeToken'] == NATIVE_TOKEN else w['prizeToken']}")
            print(f"    Prize Amount: {prize_amount_wei / 10**prize_token_decimals} ({prize_amount_wei} wei)")
            print(f"    Certificate : ipfs://{w['certificateCID']}")

        print("\nCreating competition...")

        total_prize_amount = sum(parse_prize_wei(w["prizeAmount"], prize_token_decimals) for w in winners_data)
        required_native = 0
        if treasury_fee > 0 and fee_token == NATIVE_TOKEN:
            required_native += treasury_fee
        if first_prize_token == NATIVE_TOKEN:
            required_native += total_prize_amount

        tx_kwargs = {"sender": akun}
        if required_native > 0:
            if akun.balance < required_native:
                print(f"Error: Account {akun.address} has insufficient Native Token balance ({akun.balance / 10**18} ETH). Required: {required_native / 10**18} ETH.")
                return
            tx_kwargs["value"] = required_native

        if treasury_fee > 0 and fee_token != NATIVE_TOKEN:
            treasury_address = contract.treasuryPlatformContract()
            erc20 = Contract(fee_token, abi=ERC20_ABI)
            fee_token_balance = erc20.balanceOf(effective_org)
            if fee_token_balance < treasury_fee:
                print(f"Error: Account {effective_org} has insufficient balance of Fee Token ({fee_token}). Balance: {fee_token_balance / 10**fee_token_decimals}, Required: {treasury_fee / 10**fee_token_decimals}.")
                return
            allowance = erc20.allowance(effective_org, treasury_address)
            if allowance < treasury_fee:
                if effective_org == akun.address:
                    print(f"\nApproving TreasuryPlatform to spend {treasury_fee} wei of fee token...")
                    erc20.approve(treasury_address, treasury_fee, sender=akun)
                else:
                    print(f"\nWarning: Fee token allowance for organization ({effective_org}) on TreasuryPlatform is insufficient.")

        if total_prize_amount > 0 and first_prize_token != NATIVE_TOKEN:
            treasury_prize_address = contract.treasuryPrizeContract()
            erc20_prize = Contract(first_prize_token, abi=ERC20_ABI)
            prize_token_balance = erc20_prize.balanceOf(effective_org)
            if prize_token_balance < total_prize_amount:
                print(f"Error: Account {effective_org} has insufficient balance of Prize Token ({first_prize_token}). Balance: {prize_token_balance / 10**prize_token_decimals}, Required: {total_prize_amount / 10**prize_token_decimals}.")
                return
            allowance_prize = erc20_prize.allowance(effective_org, treasury_prize_address)
            if allowance_prize < total_prize_amount:
                if effective_org == akun.address:
                    print(f"\nApproving TreasuryPrize to spend {total_prize_amount} wei of prize token...")
                    erc20_prize.approve(treasury_prize_address, total_prize_amount, sender=akun)
                else:
                    print(f"\nWarning: Prize token allowance for organization ({effective_org}) on TreasuryPrize is insufficient.")

        tx = contract.createCompetition(
            competition_input,
            winners_input,
            platform_fee_id,
            **tx_kwargs,
        )

        print(f"\nTX Hash        : {tx.txn_hash}")
        print("Create success!")

