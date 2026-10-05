import pytest
from ape import accounts, project, chain
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
    competition_manager.addListingToken(NATIVE_TOKEN, sender=owner)
    assert competition_manager.isTokenListed(NATIVE_TOKEN)
    assert competition_manager.isTokenActive(NATIVE_TOKEN)

    competition_manager.deactivateListingToken(NATIVE_TOKEN, sender=owner)
    token_info = competition_manager.listingToken(NATIVE_TOKEN)
    assert not token_info.isActive
    assert not competition_manager.isTokenActive(NATIVE_TOKEN)


def test_price_fee(competition_manager, owner):
    competition_manager.addListingToken(NATIVE_TOKEN, sender=owner)
    competition_manager.setPriceCompetitionFee(
        100, NATIVE_TOKEN, "Tier 1", sender=owner
    )
    fee = competition_manager.getPriceCompetitionFee(1)
    assert fee.id == 1
    assert fee.treasuryFee == 100
    assert fee.tokenAddress == NATIVE_TOKEN
    assert fee.cid == "Tier 1"


def test_price_fee_requires_listed_token(competition_manager, owner):
    # Fee token yang belum terdaftar harus ditolak.
    with pytest.raises(Exception) as exc_info:
        competition_manager.setPriceCompetitionFee(
            100, NATIVE_TOKEN, "Tier 1", sender=owner
        )
    assert exc_info.type.__name__ == "TokenNotListed"

    # Setelah terdaftar & aktif, fee bisa di-set.
    competition_manager.addListingToken(NATIVE_TOKEN, sender=owner)
    competition_manager.setPriceCompetitionFee(
        100, NATIVE_TOKEN, "Tier 1", sender=owner
    )

    # Token yang sudah nonaktif tidak boleh dipakai sebagai fee token.
    competition_manager.deactivateListingToken(NATIVE_TOKEN, sender=owner)
    with pytest.raises(Exception) as exc_info:
        competition_manager.updatePriceCompetitionFee(
            1, 200, NATIVE_TOKEN, "Tier 2", sender=owner
        )
    assert exc_info.type.__name__ == "TokenNotActive"


def test_create_competition_and_winner(competition_manager, owner, organization, participant):
    competition_manager.addListingToken(NATIVE_TOKEN, sender=owner)
    competition_manager.setPriceCompetitionFee(0, NATIVE_TOKEN, "Free", sender=owner)

    now = chain.pending_timestamp
    claim = now + 100
    competition = (
        0,                    # id (di-overwrite kontrak)
        "Hackathon",          # cid
        "1-3 member",         # formation
        organization.address, # organization
        claim,                # prizeCertificateClaim
        "certCID",            # certificateCID
        (NATIVE_TOKEN, 0),    # payment (tokenAddress, fee)
    )
    winners_data = [
        (0, 0, NATIVE_TOKEN, 1000, "winnerCertCID", 1),
    ]

    competition_manager.createCompetition(
        competition,
        (NATIVE_TOKEN, 0),
        winners_data,
        1,
        sender=organization,
        value=1000,
    )

    comp = competition_manager.getCompetition(1)
    assert comp.cid == "Hackathon"
    assert comp.organization == organization.address

    winners = competition_manager.getWinners(1)
    assert len(winners) == 1
    assert winners[0].prizeAmount == 1000

    bal_before = participant.balance
    competition_manager.setWinner(1, participant.address, 1, sender=organization)
    assert participant.balance == bal_before + 1000


def test_soulbound_nft_mint_and_transfer(competition_manager, owner, organization, participant, signer_account):
    competition_manager.addListingToken(NATIVE_TOKEN, sender=owner)
    competition_manager.setPriceCompetitionFee(0, NATIVE_TOKEN, "Free", sender=owner)

    now = chain.pending_timestamp
    claim = now + 100
    competition = (
        0, "Ended Hackathon", "1-3 member", organization.address,
        claim, "certCID", (NATIVE_TOKEN, 0),
    )
    winners_data = [
        (0, 0, NATIVE_TOKEN, 100, "winnerCertCID", 1),
    ]

    competition_manager.createCompetition(
        competition,
        (NATIVE_TOKEN, 0),
        winners_data,
        1,
        sender=organization,
        value=100,
    )

    # Majukan waktu melewati batas klaim agar minting diizinkan.
    chain.pending_timestamp = claim + 1

    uri = "ipfs://certCID"
    contract_checksum = Web3.to_checksum_address(competition_manager.address)
    participant_checksum = Web3.to_checksum_address(participant.address)

    # Single msg.sender — must match CompetitionManager.safeMintCertificateParticipant
    # keccak256(abi.encodePacked(address(this), msg.sender, _competitionId, _teamId, uri))
    msg_hash = Web3.solidity_keccak(
        ["address", "address", "uint256", "uint256", "string"],
        [contract_checksum, participant_checksum, 1, 1, uri],
    )
    signable_msg = encode_defunct(primitive=msg_hash)
    signed_msg = signer_account.sign_message(signable_msg)
    signature = signed_msg.signature

    competition_manager.safeMintCertificateParticipant(
        1, 1, signature, sender=participant,
    )

    assert competition_manager.ownerOf(0) == participant.address

    # Verify Soulbound requirement: transfer should revert.
    with pytest.raises(Exception) as exc_info:
        competition_manager.transferFrom(participant.address, owner.address, 0, sender=participant)
    assert exc_info.type.__name__ == "CertificateNonTransferable"


def test_payment_create_team_native(competition_manager, owner, organization, participant):
    # Setup: buat kompetisi dengan fee pembuatan tim 100 (native).
    competition_manager.addListingToken(NATIVE_TOKEN, sender=owner)
    competition_manager.setPriceCompetitionFee(0, NATIVE_TOKEN, "Free", sender=owner)

    now = chain.pending_timestamp
    claim = now + 100
    competition = (
        0, "compCID", "1-3 member", organization.address, claim, "certCID",
        (NATIVE_TOKEN, 100),
    )
    winners_data = [
        (0, 0, NATIVE_TOKEN, 100, "winnerCertCID", 1),
    ]

    competition_manager.createCompetition(
        competition,
        (NATIVE_TOKEN, 100),
        winners_data,
        1,
        sender=organization,
        value=100,
    )

    # Sukses: pembayaran pembuatan tim menggunakan ETH asli.
    tx = competition_manager.paymentCreateTeam(
        1, "team-payment", NATIVE_TOKEN, participant.address, organization.address, 100,
        sender=participant, value=100,
    )
    assert competition_manager.totalPaid(1, NATIVE_TOKEN) == 100

    logs = list(tx.decode_logs(competition_manager.TeamPaymentCreated))
    assert len(logs) == 1
    assert logs[0].competitionId == 1
    assert logs[0].token == NATIVE_TOKEN
    assert logs[0].event_arguments["from"] == participant.address
    assert logs[0].to == organization.address
    assert logs[0].amount == 100

    # Revert: untuk native, from harus msg.sender.
    with pytest.raises(Exception) as exc_info:
        competition_manager.paymentCreateTeam(
            1, "team-payment", NATIVE_TOKEN, owner.address, organization.address, 100,
            sender=participant, value=100,
        )
    assert exc_info.type.__name__ == "NativeFromMismatch"

    # Revert: msg.value harus sama dengan amount.
    with pytest.raises(Exception) as exc_info:
        competition_manager.paymentCreateTeam(
            1, "team-payment", NATIVE_TOKEN, participant.address, organization.address, 100,
            sender=participant, value=50,
        )
    assert exc_info.type.__name__ == "IncorrectNativeAmount"

    # Revert: penerima tidak boleh address(0).
    with pytest.raises(Exception) as exc_info:
        competition_manager.paymentCreateTeam(
            1, "team-payment", NATIVE_TOKEN, participant.address, NATIVE_TOKEN, 100,
            sender=participant, value=100,
        )
    assert exc_info.type.__name__ == "InvalidRecipient"

    # Revert: amount harus sama dengan fee kompetisi.
    with pytest.raises(Exception) as exc_info:
        competition_manager.paymentCreateTeam(
            1, "team-payment", NATIVE_TOKEN, participant.address, organization.address, 50,
            sender=participant, value=50,
        )
    assert exc_info.type.__name__ == "IncorrectFeeAmount"

