## Ideally, they have one file with the settings for the strat and deployment
## This file would allow them to configure so they can test, deploy and interact with the strategy

BADGER_DEV_MULTISIG = "0xc388750A661cC0B99784bAB2c55e1F38ff91643b"

WANT = "0xe62ec2e799305e0d367b0cc3ee2cda135bf89816"  ## WETH-SUSHI-SLP on polygon
REWARD_TOKEN = "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9"  ## Sushi Token
# REWARD_TOKEN = "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270"  ## wMatic Token

PROTECTED_TOKENS = [WANT, REWARD_TOKEN]
## Fees in Basis Points
DEFAULT_GOV_PERFORMANCE_FEE = 1000
DEFAULT_PERFORMANCE_FEE = 1000
DEFAULT_WITHDRAWAL_FEE = 50

FEES = [DEFAULT_GOV_PERFORMANCE_FEE, DEFAULT_PERFORMANCE_FEE, DEFAULT_WITHDRAWAL_FEE]

REGISTRY = "0xFda7eB6f8b7a9e9fCFd348042ae675d1d652454f"  # Multichain BadgerRegistry
