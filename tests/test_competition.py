import time
import pytest
from ape import accounts, project
from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

NATIVE_TOKEN = "0x0000000000000000000000000000000000000000"


@pytest.fixture
def owner():
    return accounts.test_accounts[0]


@pytest.fixture
def organization():
    return accounts.test_accounts[1]


@pytest.fixture
def participant():
    return accounts.test_accounts[2]


@pytest.fixture
def signer_account():
    return Account.create()


@pytest.fixture
def competition_manager(owner, signer_account):
    return owner.deploy(project.CompetitionManager, owner.address, signer_account.address)


def test_initial_state(competition_manager, owner, signer_account):
    assert competition_manager.owner() == owner.address
    assert competition_manager.signerAddress() == signer_account.address


def test_signer_update(competition_manager, owner):
    new_signer = Account.create()
    competition_manager.updateSignerAddress(new_signer.address, sender=owner)
    assert competition_manager.signerAddress() == new_signer.address


def test_listing_token(competition_manager, owner):
    assert not competition_manager.isTokenListed(NATIVE_TOKEN)
    competition_manager.addListingTokenPrize(NATIVE_TOKEN, sender=owner)
    assert competition_manager.isTokenListed(NATIVE_TOKEN)

    competition_manager.deactivateListingTokenPrize(NATIVE_TOKEN, sender=owner)
    token_info = competition_manager.listingToken(NATIVE_TOKEN)
    assert not token_info.isActive


def test_price_fee(competition_manager, owner):
    competition_manager.setPriceCompetitionFee(
        100, NATIVE_TOKEN, "Tier 1", "Standard Fee", sender=owner
    )
    fee = competition_manager.getPriceCompetitionFee(1)
    assert fee.id == 1
    assert fee.treasuryFee == 100
    assert fee.tokenAddress == NATIVE_TOKEN
    assert fee.title == "Tier 1"


def test_create_competition_and_winner(competition_manager, owner, organization, participant):
    competition_manager.addListingTokenPrize(NATIVE_TOKEN, sender=owner)
    competition_manager.setPriceCompetitionFee(0, NATIVE_TOKEN, "Free", "Free Fee", sender=owner)

    now = int(time.time())
    schedule = (now, now, now + 10, now + 10, now + 10, now + 100)
    competition_data = (
        0,
        "Hackathon",
        "Web3",
        "Build dApp",
        "Must be open source",
        competition_manager.FORMATION_1_3_MEMBER(),
        organization.address,
        schedule,
        "certCID",
        "guideCID",
    )
    winners_data = [
        (0, 0, "1st Place", NATIVE_TOKEN, 1000, "winnerCertCID"),
    ]

    tx = competition_manager.createCompetition(
        competition_data,
        winners_data,
        1,
        sender=organization,
        value=1000,
    )

    comp = competition_manager.getCompetition(1)
    assert comp.name == "Hackathon"
    assert comp.organization == organization.address

    winners = competition_manager.getWinners(1)
    assert len(winners) == 1
    assert winners[0].prizeAmount == 1000

    bal_before = participant.balance
    competition_manager.setWinner(1, participant.address, 1, sender=organization)
    assert participant.balance == bal_before + 1000


def test_soulbound_nft_mint_and_transfer(competition_manager, owner, organization, participant, signer_account, provider):
    competition_manager.addListingTokenPrize(NATIVE_TOKEN, sender=owner)
    competition_manager.setPriceCompetitionFee(0, NATIVE_TOKEN, "Free", "Free Fee", sender=owner)

    now = int(provider.chain.blocks.head.timestamp)
    # Prize certificate claim window in past so onlyCompetitionEnd passes
    schedule = (now - 100, now - 100, now - 50, now - 50, now - 50, now - 10)
    competition_data = (
        0,
        "Ended Hackathon",
        "Web3",
        "Build dApp",
        "Requirements",
        competition_manager.FORMATION_1_3_MEMBER(),
        organization.address,
        schedule,
        "certCID",
        "guideCID",
    )
    winners_data = [
        (0, 0, "1st Place", NATIVE_TOKEN, 100, "winnerCertCID"),
    ]

    competition_manager.createCompetition(
        competition_data,
        winners_data,
        1,
        sender=organization,
        value=100,
    )

    uri = f"ipfs://certCID"
    contract_checksum = Web3.to_checksum_address(competition_manager.address)
    participant_checksum = Web3.to_checksum_address(participant.address)

    msg_hash = Web3.solidity_keccak(
        ["address", "address", "address", "uint256", "string"],
        [contract_checksum, participant_checksum, participant_checksum, 1, uri],
    )
    signable_msg = encode_defunct(primitive=msg_hash)
    signed_msg = signer_account.sign_message(signable_msg)
    signature = signed_msg.signature

    tx = competition_manager.safeMintCertificateParticipant(
        1,
        signature,
        sender=participant,
    )

    assert competition_manager.ownerOf(0) == participant.address

    # Verify Soulbound requirement: transfer should revert
    with pytest.raises(Exception) as exc_info:
        competition_manager.transferFrom(participant.address, owner.address, 0, sender=participant)
    assert "Certificate NFTs are non-transferable" in str(exc_info.value)

