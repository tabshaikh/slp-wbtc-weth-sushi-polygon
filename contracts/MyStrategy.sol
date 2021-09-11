// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IController.sol";

import {IMiniChefV2} from "../interfaces/sushiswap/IMinichef.sol";
import {IUniswapRouterV2} from "../interfaces/uniswap/IUniswapRouterV2.sol";

import {BaseStrategy} from "../deps/BaseStrategy.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    address public lpComponent; // Token we provide liquidity with
    address public reward; // Token we farm and swap to want / lpComponent

    address public constant CHEF = 0x0769fd68dFb93167989C6f7254cd0D766Fb2841F; // Polygon MiniChefv2
    address public constant SUSHISWAP_ROUTER =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address public constant WMATIC = 0x0769fd68dFb93167989C6f7254cd0D766Fb2841F; // WMATIC Polygon
    address public constant wBTC = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6; // wBTC Polygon
    address public constant wETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; // wETH Polygon

    uint256 public constant pid = 3; // WBTC-WETH-SUSHI-Polygon pool ID from https://thegraph.com/legacy-explorer/subgraph/sushiswap/matic-minichef
    uint256 public slippage = 50; // in terms of bps = 0.5%
    uint256 public constant MAX_BPS = 10_000;

    // Used to signal to the Badger Tree that rewards where sent to it
    event TreeDistribution(
        address indexed token,
        uint256 amount,
        uint256 indexed blockNumber,
        uint256 timestamp
    );

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );

        /// @dev Add config here
        want = _wantConfig[0];
        reward = _wantConfig[1];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(CHEF, type(uint256).max);
        IERC20Upgradeable(reward).safeApprove(
            SUSHISWAP_ROUTER,
            type(uint256).max
        );
        // IERC20Upgradeable(want).safeApprove(gauge, type(uint256).max);
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "WBTC-WETH-Sushi-Polygon-Strategy";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public view override returns (uint256) {
        (uint256 amount, ) = IMiniChefV2(CHEF).userInfo(pid, address(this));
        return amount;
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        return balanceOfWant() > 0;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](3);
        protectedTokens[0] = want;
        protectedTokens[1] = reward;
        return protectedTokens;
    }

    /// ===== Permissioned Actions: Governance =====
    /// @notice Delete if you don't need!
    function setKeepReward(uint256 _setKeepReward) external {
        _onlyGovernance();
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        IMiniChefV2(CHEF).deposit(pid, _amount, address(this));
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        // Maybe harvest all rewards
        // withdraw
        IMiniChefV2(CHEF).withdraw(pid, balanceOfPool(), address(this));
    }

    /// @dev withdraw the specified amount of want, liquidate from lpComponent to want, paying off any necessary debt for the conversion
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        uint256 inPool = balanceOfPool();
        if (_amount > inPool) {
            _amount = inPool;
        }

        IMiniChefV2(CHEF).withdraw(pid, _amount, address(this));

        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {
        _onlyAuthorizedActors();

        uint256 _before = IERC20Upgradeable(want).balanceOf(address(this));

        // Write your code here

        IMiniChefV2(CHEF).harvest(pid, address(this));

        // Get total rewards (WMATIC)
        uint256 rewardsAmountWMATIC = IERC20Upgradeable(WMATIC).balanceOf(
            address(this)
        );

        // Swap WMATIC for Sushi(which is reward token) through path: WMATIC -> SUSHI
        address[] memory path = new address[](2);
        path[0] = WMATIC;
        path[1] = reward;
        IUniswapRouterV2(SUSHISWAP_ROUTER).swapExactTokensForTokens(
            rewardsAmountWMATIC,
            0, // TODO: should change this maybe use chainlink
            path,
            address(this),
            now
        );

        // Get total rewards (SUSHI) . this will give us the total reward as wmatic reward is swapped to sushi
        uint256 rewardsAmount = IERC20Upgradeable(reward).balanceOf(
            address(this)
        );

        // Swap half sushi to weth and half to wbtc

        // Swap Sushi for wBTC through path: SUSHI -> wBTC
        uint256 sushiTowbtcAmount = rewardsAmount.mul(5000).div(MAX_BPS);
        path = new address[](2);
        path[0] = reward;
        path[1] = wBTC;
        IUniswapRouterV2(SUSHISWAP_ROUTER).swapExactTokensForTokens(
            sushiTowbtcAmount,
            0, // TODO: should change this maybe use chainlink
            path,
            address(this),
            now
        );

        // Swap Sushi for wETH through path: SUSHI -> wETH
        uint256 sushiTowethAmount = rewardsAmount.sub(sushiTowbtcAmount);
        path = new address[](2);
        path[0] = reward;
        path[1] = wETH;
        IUniswapRouterV2(SUSHISWAP_ROUTER).swapExactTokensForTokens(
            sushiTowethAmount,
            0, // TODO: should change this maybe use chainlink
            path,
            address(this),
            now
        );

        // Add liquidity for WBTC-WETH pool
        // check if they are needed to be added in the exact ratio or router takes care of it
        uint256 wbtcIn = IERC20Upgradeable(wBTC).balanceOf(address(this));
        uint256 wethIn = IERC20Upgradeable(wETH).balanceOf(address(this));

        IUniswapRouterV2(SUSHISWAP_ROUTER).addLiquidity(
            wBTC,
            wETH,
            wbtcIn,
            wethIn,
            wbtcIn.mul(slippage).div(MAX_BPS),
            wethIn.mul(slippage).div(MAX_BPS),
            address(this),
            now
        );

        uint256 earned = IERC20Upgradeable(want).balanceOf(address(this)).sub(
            _before
        );

        /// @notice Keep this in so you get paid!
        (
            uint256 governancePerformanceFee,
            uint256 strategistPerformanceFee
        ) = _processPerformanceFees(earned);

        // TODO: If you are harvesting a reward token you're not compounding
        // You probably still want to capture fees for it
        // // Process Sushi rewards if existing
        // if (sushiAmount > 0) {
        //     // Process fees on Sushi Rewards
        //     // NOTE: Use this to receive fees on the reward token
        //     _processRewardsFees(sushiAmount, SUSHI_TOKEN);

        //     // Transfer balance of Sushi to the Badger Tree
        //     // NOTE: Send reward to badgerTree
        //     uint256 sushiBalance = IERC20Upgradeable(SUSHI_TOKEN).balanceOf(address(this));
        //     IERC20Upgradeable(SUSHI_TOKEN).safeTransfer(badgerTree, sushiBalance);
        //
        //     // NOTE: Signal the amount of reward sent to the badger tree
        //     emit TreeDistribution(SUSHI_TOKEN, sushiBalance, block.number, block.timestamp);
        // }

        /// @dev Harvest event that every strategy MUST have, see BaseStrategy
        emit Harvest(earned, block.number);

        /// @dev Harvest must return the amount of want increased
        return earned;
    }

    // Alternative Harvest with Price received from harvester, used to avoid exessive front-running
    function harvest(uint256 price)
        external
        whenNotPaused
        returns (uint256 harvested)
    {}

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee, make sure to use it to get paid!
    function _processPerformanceFees(uint256 _amount)
        internal
        returns (
            uint256 governancePerformanceFee,
            uint256 strategistPerformanceFee
        )
    {
        governancePerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistPerformanceFee = _processFee(
            want,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token)
        internal
        returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee)
    {
        governanceRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }
}
