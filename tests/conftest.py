from brownie import (
    accounts,
    interface,
    Controller,
    SettV3,
    MyStrategy,
)
from config import (
    BADGER_DEV_MULTISIG,
    WANT,
    REWARD_TOKEN,
    PROTECTED_TOKENS,
    FEES,
)
from dotmap import DotMap
import pytest


@pytest.fixture
def deployed():
    """
    Deploys, vault, controller and strats and wires them up for you to test
    """
    deployer = accounts[0]

    strategist = deployer
    keeper = deployer
    guardian = deployer

    governance = accounts.at(BADGER_DEV_MULTISIG, force=True)

    controller = Controller.deploy({"from": deployer})
    controller.initialize(
        BADGER_DEV_MULTISIG, strategist, keeper, BADGER_DEV_MULTISIG, {"from": deployer}
    )

    sett = SettV3.deploy({"from": deployer})
    sett.initialize(
        WANT,
        controller,
        BADGER_DEV_MULTISIG,
        keeper,
        guardian,
        False,
        "prefix",
        "PREFIX",
    )

    sett.unpause({"from": governance})
    controller.setVault(WANT, sett, {"from": deployer})

    ## TODO: Add guest list once we find compatible, tested, contract
    # guestList = VipCappedGuestListWrapperUpgradeable.deploy({"from": deployer})
    # guestList.initialize(sett, {"from": deployer})
    # guestList.setGuests([deployer], [True])
    # guestList.setUserDepositCap(100000000)
    # sett.setGuestList(guestList, {"from": governance})

    ## Start up Strategy
    strategy = MyStrategy.deploy({"from": deployer})
    strategy.initialize(
        BADGER_DEV_MULTISIG,
        strategist,
        controller,
        keeper,
        guardian,
        PROTECTED_TOKENS,
        FEES,
    )

    ## Tool that verifies bytecode (run independently) <- Webapp for anyone to verify

    ## Set up tokens
    want = interface.IERC20(WANT)
    # lpComponent = interface.IERC20(LP_COMPONENT)
    rewardToken = interface.IERC20(REWARD_TOKEN)

    ## Wire up Controller to Strart
    ## In testing will pass, but on live it will fail
    controller.approveStrategy(WANT, strategy, {"from": governance})
    controller.setStrategy(WANT, strategy, {"from": deployer})

    WETH = strategy.wETH()
    WBTC = strategy.wBTC()
    SUSHI = strategy.reward()
    MATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"
    wbtc = interface.IERC20(WBTC)
    weth = interface.IERC20(WETH)
    sushi = interface.IERC20(SUSHI)

    ## Uniswap some tokens here
    router = interface.IUniswapRouterV2(strategy.SUSHISWAP_ROUTER())

    sushi.approve(router.address, 999999999999999999999999999999, {"from": deployer})
    wbtc.approve(router.address, 999999999999999999999999999999, {"from": deployer})
    weth.approve(router.address, 999999999999999999999999999999, {"from": deployer})

    deposit_amount = 2500 * 10 ** 18

    # Buy weth through path ETH -> MATIC -> WETH
    router.swapExactETHForTokens(
        0,
        [MATIC, WETH],
        deployer,
        9999999999999999,
        {"value": deposit_amount, "from": deployer},
    )

    # Buy wbtc with path ETH -> MATIC -> WETH -> WBTC
    router.swapExactETHForTokens(
        0,
        [MATIC, WETH, WBTC],
        deployer,
        9999999999999999,
        {"value": deposit_amount, "from": deployer},
    )

    print("Balance of WBTC: ", wbtc.balanceOf(deployer))
    print("Balance of WETH: ", weth.balanceOf(deployer))

    # Add WETH-SUSHI liquidity
    router.addLiquidity(
        WBTC,
        WETH,
        wbtc.balanceOf(deployer),
        weth.balanceOf(deployer),
        wbtc.balanceOf(deployer) * 0.005,
        weth.balanceOf(deployer) * 0.005,
        deployer,
        9999999999999999,
        {"from": deployer},
    )

    print("Initial Want Balance: ", want.balanceOf(deployer.address))
    assert want.balanceOf(deployer) > 0

    return DotMap(
        deployer=deployer,
        controller=controller,
        vault=sett,
        sett=sett,
        strategy=strategy,
        # guestList=guestList,
        want=want,
        rewardToken=rewardToken,
    )


## Contracts ##


@pytest.fixture
def vault(deployed):
    return deployed.vault


@pytest.fixture
def sett(deployed):
    return deployed.sett


@pytest.fixture
def controller(deployed):
    return deployed.controller


@pytest.fixture
def strategy(deployed):
    return deployed.strategy


## Tokens ##


@pytest.fixture
def want(deployed):
    return deployed.want


@pytest.fixture
def tokens():
    return [WANT, REWARD_TOKEN]


## Accounts ##


@pytest.fixture
def deployer(deployed):
    return deployed.deployer


@pytest.fixture
def strategist(strategy):
    return accounts.at(strategy.strategist(), force=True)


@pytest.fixture
def settKeeper(vault):
    return accounts.at(vault.keeper(), force=True)


@pytest.fixture
def strategyKeeper(strategy):
    return accounts.at(strategy.keeper(), force=True)
