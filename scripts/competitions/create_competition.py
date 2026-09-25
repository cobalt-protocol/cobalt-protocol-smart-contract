#!/usr/bin/env python3
import json
import os
from datetime import datetime, timezone, timedelta

import click
import requests
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


upload_cache = {}


def upload_file_to_kubo_ipfs(file_path: str, endpoint: str = None) -> str:
    abs_path = os.path.abspath(file_path)
    if abs_path in upload_cache:
        return upload_cache[abs_path]

    if endpoint is None:
        base_url = os.getenv("KUBO_API_URL", "http://localhost:5001").rstrip("/")
        endpoint = f"{base_url}/api/v0/add"

    if not os.path.exists(file_path):
        print(f"Warning: File '{file_path}' not found.")
        return ""

    filename = os.path.basename(file_path)
    with open(file_path, "rb") as f:
        files = {"file": (filename, f.read())}

    try:
        response = requests.post(endpoint, files=files, timeout=30)
        response.raise_for_status()
        result = response.json()
        cid = result.get("Hash")
        if cid:
            upload_cache[abs_path] = cid
            return cid
        raise ValueError(f"No Hash in Kubo response: {result}")
    except Exception as e:
        print(f"Warning: Failed to upload file '{file_path}' to Kubo IPFS ({endpoint}): {e}")
        return ""


def upload_to_kubo_ipfs(data: dict, endpoint: str = None) -> str:
    if endpoint is None:
        base_url = os.getenv("KUBO_API_URL", "http://localhost:5001").rstrip("/")
        endpoint = f"{base_url}/api/v0/add"

    json_bytes = json.dumps(data, indent=2).encode("utf-8")
    files = {"file": ("competition_metadata.json", json_bytes, "application/json")}

    try:
        response = requests.post(endpoint, files=files, timeout=10)
        response.raise_for_status()
        result = response.json()
        cid = result.get("Hash")
        if cid:
            return cid
        raise ValueError(f"No Hash in Kubo response: {result}")
    except Exception as e:
        print(f"Warning: Failed to upload to Kubo IPFS ({endpoint}): {e}")
        return ""


def is_dummy_cid(val: str) -> bool:
    if not val or not isinstance(val, str):
        return True
    val = val.strip()
    if not val:
        return True
    if os.path.exists(val):
        return True
    if "CID" in val or "dummy" in val.lower() or val.startswith("QmDefault") or len(val) < 30:
        return True
    return False


def resolve_or_upload_file_cid(input_val: str, default_file_path: str, file_label: str) -> str:
    if input_val and os.path.exists(input_val):
        print(f"Uploading {file_label} file '{input_val}' to Kubo IPFS...")
        cid = upload_file_to_kubo_ipfs(input_val)
        if cid:
            print(f"Uploaded {file_label} CID: {cid}")
            return cid

    if is_dummy_cid(input_val):
        if os.path.exists(default_file_path):
            print(f"Uploading default {file_label} file ({os.path.basename(default_file_path)}) to Kubo IPFS...")
            cid = upload_file_to_kubo_ipfs(default_file_path)
            if cid:
                print(f"Uploaded {file_label} CID: {cid}")
                return cid
            else:
                print(f"Warning: Failed to upload default {file_label} file to Kubo IPFS.")
        else:
            print(f"Warning: Default {file_label} file not found at '{default_file_path}'.")

    return input_val


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

        with open(input_json, "r") as f:
            data = json.load(f)

        competition = data["competition"]
        winners_data = data["winners"]
        platform_fee_id = competition.get("platformFeeId", 1)

        fee_data = contract.getPriceCompetitionFee(platform_fee_id)
        if fee_data.id == 0:
            print(f"Error: Fee option ID {platform_fee_id} does not exist in CompetitionManager.")
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

        listed_token = contract.listingToken(first_prize_token)
        if listed_token.id == 0:
            print(f"Error: Prize token ({first_prize_token}) is not listed in CompetitionManager.")
            return
        if not listed_token.isActive:
            print(f"Error: Prize token ({first_prize_token}) is listed but deactivated in CompetitionManager.")
            return

        if fee_token == NATIVE_TOKEN:
            print("Fee Token     : Native Token")
        else:
            print(f"Fee Token     : {fee_token}")

        print(f"Fee Option ID : {platform_fee_id} (CID: {fee_data.cid})")
        print(f"Treasury Fee  : {treasury_fee / 10**18} ({treasury_fee} wei)")

        try:
            chain_now_ts = int(provider.chain.blocks.head.timestamp)
        except Exception:
            chain_now_ts = int(datetime.now(timezone.utc).timestamp())

        # Timeline schedule with 5 seconds step for each stage starting from chain_now_ts
        interval_seconds = 5
        reg_window = chain_now_ts + interval_seconds
        comp_window = reg_window + interval_seconds
        sub_deadline = comp_window + interval_seconds
        judging_review = sub_deadline + interval_seconds
        result_announcement = judging_review + interval_seconds
        prize_claim = result_announcement + interval_seconds
        duration_desc = "30 seconds (5s intervals)"

        org_setting = competition.get("organization", NATIVE_TOKEN)
        effective_org = akun.address if not org_setting or org_setting == NATIVE_TOKEN else org_setting
        formation_input = competition.get("formation", "1-3 member")

        SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
        DEFAULT_CERT_FILE = os.path.join(SCRIPT_DIR, "1600w-CzqD3cdSM08.webp")
        DEFAULT_GUIDEBOOK_FILE = os.path.join(SCRIPT_DIR, "2. Tugas Studi Kasus  Skema programmer-Dapur Ina Aina.pdf")

        # Resolve/upload competition certificate CID
        comp_cert_input = competition.get("certificateCID", "")
        comp_cert_cid = resolve_or_upload_file_cid(comp_cert_input, DEFAULT_CERT_FILE, "Competition Certificate")
        if comp_cert_cid:
            competition["certificateCID"] = comp_cert_cid

        # Resolve/upload competition guidebook CID
        guidebook_input = competition.get("guideBookCID", "")
        guidebook_cid = resolve_or_upload_file_cid(guidebook_input, DEFAULT_GUIDEBOOK_FILE, "Guidebook")
        if guidebook_cid:
            competition["guideBookCID"] = guidebook_cid

        # Resolve/upload winner certificate CIDs
        for i, w in enumerate(winners_data):
            w_cert_input = w.get("certificateCID", "")
            w_cert_cid = resolve_or_upload_file_cid(w_cert_input, DEFAULT_CERT_FILE, f"Winner #{i+1} Certificate")
            if w_cert_cid:
                w["certificateCID"] = w_cert_cid

        # Collect off-chain attributes matching reference commit 62dcb3aede2516c5756f76648a7382cf9e80bd54
        metadata_payload = {
            "name": competition.get("name", ""),
            "category": competition.get("category", ""),
            "description": competition.get("description", ""),
            "requirements": competition.get("requirements", ""),
            "formation": formation_input,
            "schedule": {
                "registrationWindow": reg_window,
                "competitionWindow": comp_window,
                "submissionDeadline": sub_deadline,
                "judgingReview": judging_review,
                "resultAnnouncement": result_announcement,
                "prizeCertificateClaim": prize_claim,
            },
            "certificateCID": competition.get("certificateCID", ""),
            "guideBookCID": competition.get("guideBookCID", ""),
            "winners": [
                {
                    "title": w.get("title", f"Winner #{i+1}"),
                    "prizeToken": w.get("prizeToken"),
                    "prizeAmount": w.get("prizeAmount"),
                    "certificateCID": w.get("certificateCID", ""),
                }
                for i, w in enumerate(winners_data)
            ],
        }

        comp_cid = competition.get("cid", "")
        if not comp_cid or any(k in competition for k in ["name", "category", "description", "requirements", "schedule", "guideBookCID"]):
            print("\nUploading competition metadata to Kubo IPFS (http://localhost:5001/api/v0/add)...")
            uploaded_cid = upload_to_kubo_ipfs(metadata_payload)
            if uploaded_cid:
                comp_cid = uploaded_cid
                print(f"Uploaded Metadata CID: {comp_cid}")
            else:
                print("Warning: Kubo upload failed or returned empty Hash. Using fallback CID.")
                comp_cid = comp_cid or "QmDefaultCompetitionMetadataCID"

        competition_input = (
            0,
            comp_cid,
            formation_input,
            org_setting,
            prize_claim,
            competition["certificateCID"],
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
                w["prizeToken"],
                prize_amount_wei,
                w["certificateCID"],
            ))

        claim_dt = datetime.fromtimestamp(prize_claim, tz=timezone.utc)

        print(f"\n{'='*50}")
        print("Competition Details & Schedule (5s Intervals)")
        print(f"{'='*50}")
        print(f"CID                     : ipfs://{comp_cid}")
        print(f"Formation               : {formation_input}")
        print(f"Organization            : {effective_org}")
        print(f"Registration Window End : {datetime.fromtimestamp(reg_window, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')} ({reg_window})")
        print(f"Competition Window End  : {datetime.fromtimestamp(comp_window, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')} ({comp_window})")
        print(f"Submission Deadline     : {datetime.fromtimestamp(sub_deadline, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')} ({sub_deadline})")
        print(f"Judging Review End      : {datetime.fromtimestamp(judging_review, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')} ({judging_review})")
        print(f"Result Announcement     : {datetime.fromtimestamp(result_announcement, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')} ({result_announcement})")
        print(f"Prize Certificate Claim : {claim_dt.strftime('%Y-%m-%d %H:%M:%S UTC')} ({prize_claim})")
        print(f"Certificate             : ipfs://{competition['certificateCID']}")

        print(f"\n{'='*50}")
        print(f"Winners ({len(winners_data)} total)")
        print(f"{'='*50}")
        for i, w in enumerate(winners_data):
            prize_amount_wei = parse_prize_wei(w["prizeAmount"], prize_token_decimals)
            w_title = w.get("title", f"Winner #{i+1}")
            print(f"  [{i}] {w_title}")
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
            treasury_address = contract.address
            erc20 = Contract(fee_token, abi=ERC20_ABI)
            fee_token_balance = erc20.balanceOf(effective_org)
            if fee_token_balance < treasury_fee:
                print(f"Error: Account {effective_org} has insufficient balance of Fee Token ({fee_token}). Balance: {fee_token_balance / 10**fee_token_decimals}, Required: {treasury_fee / 10**fee_token_decimals}.")
                return
            allowance = erc20.allowance(effective_org, treasury_address)
            if allowance < treasury_fee:
                if effective_org == akun.address:
                    print(f"\nApproving CompetitionManager to spend {treasury_fee} wei of fee token...")
                    erc20.approve(treasury_address, treasury_fee, sender=akun)
                else:
                    print(f"\nWarning: Fee token allowance for organization ({effective_org}) on CompetitionManager is insufficient.")

        if total_prize_amount > 0 and first_prize_token != NATIVE_TOKEN:
            treasury_prize_address = contract.address
            erc20_prize = Contract(first_prize_token, abi=ERC20_ABI)
            prize_token_balance = erc20_prize.balanceOf(effective_org)
            if prize_token_balance < total_prize_amount:
                print(f"Error: Account {effective_org} has insufficient balance of Prize Token ({first_prize_token}). Balance: {prize_token_balance / 10**prize_token_decimals}, Required: {total_prize_amount / 10**prize_token_decimals}.")
                return
            allowance_prize = erc20_prize.allowance(effective_org, treasury_prize_address)
            if allowance_prize < total_prize_amount:
                if effective_org == akun.address:
                    print(f"\nApproving CompetitionManager to spend {total_prize_amount} wei of prize token...")
                    erc20_prize.approve(treasury_prize_address, total_prize_amount, sender=akun)
                else:
                    print(f"\nWarning: Prize token allowance for organization ({effective_org}) on CompetitionManager is insufficient.")

        tx = contract.createCompetition(
            competition_input,
            winners_input,
            platform_fee_id,
            **tx_kwargs,
        )

        print(f"\nTX Hash        : {tx.txn_hash}")
        print("Create success!")

