// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../lib/WeightedPool.sol";
import "@balancer-labs/interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/interfaces/contracts/vault/IVault.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../lib/SupportLib.sol";

struct PoolSettings {
    string poolName;
    string poolSymbol;
    uint256 tolerance;
    address [] poolTokens;
}

struct PoolAdjustments {
    IVault.ExitPoolRequest newExitRequest;
    IVault.JoinPoolRequest newJoinRequest;
}

abstract contract BaseWeightedUtils is ReentrancyGuard, Pausable {
    using SafeMath for uint256;

    uint256 public constant PERCENTAGE_DENOMINATOR = 100;
    mapping(address => PoolSettings) public weightedPools; // Pools and their prices
    mapping(address => bool) public isManager; // Managers that can call special functions
    mapping(address => address) public tokenFeeds; // Token mappings from oracle
    IVault internal immutable vault;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     */
    constructor(address vaultAddress) {
        vault = IVault(vaultAddress);
        isManager[msg.sender] = true;

        // set up the token price feed mapping
        tokenFeeds[0xBAAB46E28388d2779e6E31Fd00cF0e5Ad95E327B] = 0x128fE88eaa22bFFb868Bb3A584A54C96eE24014b; // WBTCv2
        tokenFeeds[0x471EcE3750Da237f93B8E339c536989b8978a438] = 0x0568fD19986748cEfF3301e55c0eb1E729E0Ab7e; // CELO
        tokenFeeds[0x122013fd7dF1C6F636a5bb8f03108E876548b455] = 0x1FcD30A73D67639c1cD89ff5746E7585731c083B; // WETHv2
        tokenFeeds[0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73] = 0x3D207061Dbe8E2473527611BFecB87Ff12b28dDa; // CEUR
        tokenFeeds[0x72d7f41eF46a988b13530F67423B36CD9cADBc3a] = 0x6b6a4c71ec3858A024f3f0Ee44bb0AdcBEd3DcC2; // LINK
        tokenFeeds[0x2A3684e9Dc20B857375EA04235F2F7edBe818FA7] = 0xc7A353BaE210aed958a1A2928b654938EC59DaB2; // USDC
        tokenFeeds[0xf6D198Cd2A85bB2F3021cDBDAb6B878474079Be7] = 0x5e37AF40A7A344ec9b03CCD34a250F3dA9a20B02; // USDT
    }

    /**
     * @notice Set a new token oracle feed
     *
     * @param token - Token address
     * @param feed - Oracle feed address
     */
    function setTokenFeed(address token, address feed) external onlyManager {
        tokenFeeds[token] = feed;
    }

    /**
     * @notice Add a new manager to the collection of managers
     *
     * @param manager - Manager to add
     */
    function addManager(address manager) external onlyManager {
        require(manager != address(0), "Invalid address");
        require(!isManager[manager], "Address is already a manager");
        isManager[manager] = true;
    }

    /**
     * @notice Remove a manager to the collection of managers
     *
     * @param manager - Manager to remove
     */
    function removeManager(address manager) external onlyManager {
        require(isManager[manager], "Address isn't a manager");
        isManager[manager] = false;
    }

    /**
     * @notice returns the oracle supplied price for the requested token
     *
     * @param tokenAddress - Token to find a price for
     */
     function getTokenPrice(address tokenAddress) public view returns (int) {
        address feedAddress = tokenFeeds[tokenAddress];
        require(feedAddress != address(0), "Token not supported");
        
        AggregatorV3Interface dataFeed = AggregatorV3Interface(feedAddress);
        (,int tokenPrice,,,) = dataFeed.latestRoundData();
        
        return tokenPrice;
    }

    /**
     * @notice Calculates a number of tokens to add or remove to rebalance pricing
     *
     * @param poolAddress - Address of pool being worked on.
     */
     function calculateBalancing(address poolAddress) public view onlyManager whenNotPaused returns (PoolAdjustments memory) {
        IWeightedPool weightedPool = IWeightedPool(poolAddress);
        bytes32 poolId = weightedPool.getPoolId();

        (IERC20[] memory tokens, uint256[] memory balances,) = vault.getPoolTokens(poolId);
        
        uint256[] memory normalizedWeights = weightedPool.getNormalizedWeights();
        
        uint256[] memory oraclePrices = new uint256[](tokens.length);
        int256[] memory priceDeltas = new int256[](tokens.length);
        
        // Get oracle prices and compute deltas
        for (uint256 i = 0; i < tokens.length; i++) {
            oraclePrices[i] = uint256(getTokenPrice(address(tokens[i])));
            
            uint256 poolTokenPrice = 0;
            if (balances[i] > 0) {
                poolTokenPrice = balances[0].mul(normalizedWeights[0]).div(balances[i].mul(normalizedWeights[i]));
            }
            
            // Handle potential underflow
            if (int256(oraclePrices[i]) >= int256(poolTokenPrice)) {
                priceDeltas[i] = int256(oraclePrices[i].sub(poolTokenPrice));
            } else {
                priceDeltas[i] = 0;
            }
        }
        
        uint256[] memory tokenBalancesToAdd = new uint256[](tokens.length);
        uint256[] memory tokenBalancesToRemove = new uint256[](tokens.length);

        bool isJoin = false;
        bool isExit = false;
        uint256 poolTolerance = weightedPools[poolAddress].tolerance;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (priceDeltas[i] >= int256(poolTolerance)) {
                tokenBalancesToRemove[i] = balances[i].mul(poolTolerance).div(PERCENTAGE_DENOMINATOR);
                isExit = true;
            } else if (priceDeltas[i] <= -int256(poolTolerance)) {
                tokenBalancesToAdd[i] = balances[i].mul(poolTolerance).div(PERCENTAGE_DENOMINATOR);
                isJoin = true;
            }
        }
        
        IAsset[] memory assets = SupportLib._convertERC20sToAssets(tokens);
        PoolAdjustments memory poolAdjustments;

        if (isExit) {
            poolAdjustments.newExitRequest = IVault.ExitPoolRequest({
                assets: assets,
                userData: "",
                toInternalBalance: true,
                minAmountsOut: tokenBalancesToRemove
            });
        }

        if (isJoin) {
            poolAdjustments.newJoinRequest = IVault.JoinPoolRequest({
                assets: assets,
                userData: "",
                fromInternalBalance: true,
                maxAmountsIn: tokenBalancesToAdd
            });
        }

        return poolAdjustments;
    }

    /**
     * @notice Pause sensitive functions
     */
    function pause() external onlyManager {
        _pause();
    }

    /**
     * @notice Unpause sensitive functions
     */
    function unpause() external onlyManager {
        _unpause();
    }

    /**
     * @dev Modifier to restrict access to managers
     */
    modifier onlyManager() {
        require(isManager[msg.sender], "Not a manager");
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
