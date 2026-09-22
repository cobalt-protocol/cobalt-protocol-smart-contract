import pytest
from ape import accounts, project
from ape.utils import ZERO_ADDRESS


@pytest.fixture
def owner():
    return accounts.test_accounts[0]


@pytest.fixture
def organization():
    return accounts.test_accounts[1]


@pytest.fixture
def recipient():
    return accounts.test_accounts[2]


@pytest.fixture
def price_competition_manager(owner):
    return owner.deploy(project.PriceCompetitionManager, owner)


@pytest.fixture
def treasury_platform(owner):
    return owner.deploy(project.TreasuryPlatform, owner)


@pytest.fixture
def listing_token_prize(owner):
    return owner.deploy(project.ListingTokenPrizeContract, owner)


@pytest.fixture
def treasury_prize(owner):
    return owner.deploy(project.TreasuryPrize, owner)


@pytest.fixture
def competition_manager(
    owner,
    price_competition_manager,
    treasury_platform,
    listing_token_prize,
    treasury_prize,
):
    return owner.deploy(
        project.CompetitionManager,
        owner,
        price_competition_manager.address,
        treasury_platform.address,
        listing_token_prize.address,
        treasury_prize.address,
    )


def test_initial_state(
    competition_manager,
    owner,
    price_competition_manager,
    treasury_platform,
    listing_token_prize,
    treasury_prize,
):
    assert competition_manager.owner() == owner
    assert (
        competition_manager.priceCompetitionManagerContract()
        == price_competition_manager.address
    )
    assert competition_manager.treasuryPlatformContract() == treasury_platform.address
    assert (
        competition_manager.listingTokenPrizeContract() == listing_token_prize.address
    )
    assert competition_manager.treasuryPrizeContract() == treasury_prize.address
