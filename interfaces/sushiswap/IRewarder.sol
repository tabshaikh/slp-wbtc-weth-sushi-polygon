// SPDX-License-Identifier: MIT

pragma solidity ^0.6.7;
import {SafeERC20, IERC20} from "deps/@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IRewarder {
    using SafeERC20 for IERC20;

    function onSushiReward(
        uint256 pid,
        address user,
        address recipient,
        uint256 sushiAmount,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 sushiAmount
    ) external view returns (IERC20[] memory, uint256[] memory);
}
