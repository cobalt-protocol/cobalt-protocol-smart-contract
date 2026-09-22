import json
import os
from datetime import datetime, timezone, timedelta

import click
from ape import accounts, networks, project, Contract
from dotenv import load_dotenv

load_dotenv()

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


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

        if fee_token == NATIVE_TOKEN:
            print("Fee Token     : Native Token")
        else:
            print(f"Fee Token     : {fee_token}")

        print(f"Fee Option ID : {platform_fee_id} ({fee_data.title} - {fee_data.description})")
        print(f"Treasury Fee  : {treasury_fee / 10**18} ({treasury_fee} wei)")

        now = datetime.now(timezone.utc)
        now_ts = int(now.timestamp())
        if "durationInSeconds" in competition:
            duration_seconds = competition["durationInSeconds"]
            duration_desc = f"{duration_seconds} seconds"
            end_at_dt = now + timedelta(seconds=duration_seconds)
        elif "durationInDays" in competition:
            duration_days = competition["durationInDays"]
            duration_desc = f"{duration_days} days"
            end_at_dt = now + timedelta(days=duration_days)
        else:
            duration_desc = "10 seconds"
            end_at_dt = now + timedelta(seconds=10)

        end_at_ts = int(end_at_dt.timestamp())

        if "schedule" in competition and isinstance(competition["schedule"], dict):
            sched = competition["schedule"]
            reg_window = sched.get("registrationWindow", now_ts) or now_ts
            comp_window = sched.get("competitionWindow", now_ts) or now_ts
            sub_deadline = sched.get("submissionDeadline", end_at_ts) or end_at_ts
            judging = sched.get("judgingReview", end_at_ts) or end_at_ts
            announcement = sched.get("resultAnnouncement", end_at_ts) or end_at_ts
            prize_claim = sched.get("prizeCertificateClaim", end_at_ts) or end_at_ts
        else:
            reg_window = now_ts
            comp_window = now_ts
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

        competition_input = (
            0,
            competition["name"],
            competition["category"],
            competition["description"],
            competition["requirements"],
            akun.address,
            schedule_tuple,
            competition["certificateCID"],
            competition.get("guideBookCID", ""),
        )

        def parse_prize_wei(val):
            f_val = float(val)
            return int(f_val * 10**18) if f_val < 10**9 else int(f_val)

        winners_input = []
        for w in winners_data:
            prize_amount_wei = parse_prize_wei(w["prizeAmount"])
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
            prize_amount_wei = parse_prize_wei(w["prizeAmount"])
            print(f"  [{i}] {w['title']}")
            print(f"    Prize Token : {'Native Token' if w['prizeToken'] == NATIVE_TOKEN else w['prizeToken']}")
            print(f"    Prize Amount: {prize_amount_wei / 10**18} ({prize_amount_wei} wei)")
            print(f"    Certificate : ipfs://{w['certificateCID']}")

        print("\nCreating competition...")

        total_prize_amount = sum(parse_prize_wei(w["prizeAmount"]) for w in winners_data)
        required_native = 0
        if treasury_fee > 0 and fee_token == NATIVE_TOKEN:
            required_native += treasury_fee
        if first_prize_token == NATIVE_TOKEN:
            required_native += total_prize_amount

        tx_kwargs = {"sender": akun}
        if required_native > 0:
            tx_kwargs["value"] = required_native

        if treasury_fee > 0 and fee_token != NATIVE_TOKEN:
            treasury_address = contract.treasuryPlatformContract()
            erc20 = Contract(fee_token)
            allowance = erc20.allowance(akun.address, treasury_address)
            if allowance < treasury_fee:
                print(f"\nApproving TreasuryPlatform to spend {treasury_fee} wei of fee token...")
                erc20.approve(treasury_address, treasury_fee, sender=akun)

        if total_prize_amount > 0 and first_prize_token != NATIVE_TOKEN:
            treasury_prize_address = contract.treasuryPrizeContract()
            erc20_prize = Contract(first_prize_token)
            allowance_prize = erc20_prize.allowance(akun.address, treasury_prize_address)
            if allowance_prize < total_prize_amount:
                print(f"\nApproving TreasuryPrize to spend {total_prize_amount} wei of prize token...")
                erc20_prize.approve(treasury_prize_address, total_prize_amount, sender=akun)

        tx = contract.createCompetition(
            competition_input,
            winners_input,
            platform_fee_id,
            **tx_kwargs,
        )

        print(f"\nTX Hash        : {tx.txn_hash}")
        print("Create success!")

