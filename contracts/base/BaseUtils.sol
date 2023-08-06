// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../lib/SupportLib.sol";

abstract contract BaseUtils is ReentrancyGuard {
    address public manager;

    /**
     * @notice Transfer the manager to a new address
     * @dev Only one manager can presently be set
     *
     * @param supportedManager - New manager.
     */
    function transferManagement(address supportedManager) public restricted {
        manager = supportedManager;
    }

    /**
     * @notice returns the array index containing supplied address
     *
     * @param value - Address to find
     */
    function getTokenPrice(address value) public view returns (int) {
        int tokenPrice = 0;

        if (value == address(0xBAAB46E28388d2779e6E31Fd00cF0e5Ad95E327B)) { // WBTCv2
            AggregatorV3Interface dataFeed = AggregatorV3Interface(
                0x128fE88eaa22bFFb868Bb3A584A54C96eE24014b
            );

            // prettier-ignore
            (
                /* uint80 roundID */,
                tokenPrice,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = dataFeed.latestRoundData();    
        } else if (value == address(0x471EcE3750Da237f93B8E339c536989b8978a438)) { // CELO
            AggregatorV3Interface dataFeed = AggregatorV3Interface(
                0x0568fD19986748cEfF3301e55c0eb1E729E0Ab7e
            );
            // prettier-ignore
            (
                /* uint80 roundID */,
                tokenPrice,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = dataFeed.latestRoundData();
        } else if (value == address(0x122013fd7dF1C6F636a5bb8f03108E876548b455)) { // WETHv2
            AggregatorV3Interface dataFeed = AggregatorV3Interface(
                0x1FcD30A73D67639c1cD89ff5746E7585731c083B
            );
            // prettier-ignore
            (
                /* uint80 roundID */,
                tokenPrice,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
             ) = dataFeed.latestRoundData();
        } else if (value == address(0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73)) { // CEUR
            AggregatorV3Interface dataFeed = AggregatorV3Interface(
                0x3D207061Dbe8E2473527611BFecB87Ff12b28dDa
            );
            // prettier-ignore
            (
                /* uint80 roundID */,
                tokenPrice,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = dataFeed.latestRoundData();
        } else if (value == address(0x72d7f41eF46a988b13530F67423B36CD9cADBc3a)) { // LINK
            AggregatorV3Interface dataFeed = AggregatorV3Interface(
                0x6b6a4c71ec3858A024f3f0Ee44bb0AdcBEd3DcC2
            );
            // prettier-ignore
            (
                /* uint80 roundID */,
                tokenPrice,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = dataFeed.latestRoundData();
        } else if (value == address(0x2A3684e9Dc20B857375EA04235F2F7edBe818FA7)) { // USDC
            AggregatorV3Interface dataFeed = AggregatorV3Interface(
                0xc7A353BaE210aed958a1A2928b654938EC59DaB2
            );
            // prettier-ignore
            (
                /* uint80 roundID */,
                tokenPrice,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = dataFeed.latestRoundData();
        } else if (value == address(0xf6D198Cd2A85bB2F3021cDBDAb6B878474079Be7)) { // USDT
            AggregatorV3Interface dataFeed = AggregatorV3Interface(
                0x5e37AF40A7A344ec9b03CCD34a250F3dA9a20B02
            );
            // prettier-ignore
            (
                /* uint80 roundID */,
                tokenPrice,
                /*uint startedAt*/,
                /*uint timeStamp*/,
                /*uint80 answeredInRound*/
            ) = dataFeed.latestRoundData();
        } else {
            revert();
        }

        return tokenPrice;
    }

    /**
     * @dev Modifier to restrict access to the set manager
     */
    modifier restricted() {
        require(msg.sender == manager);
        _;
    }

    /**
     * @dev Modifier to check token allowance
     *
     * @param amount - Amount that is to be transferred
     * @param tokenAddress - Collateral token to check
     */
    modifier checkAllowance(uint amount, address tokenAddress) {
        IERC20 token = IERC20(tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "Error");
        _;
    }
}
