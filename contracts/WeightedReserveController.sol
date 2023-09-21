// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./base/BaseWeightedUtils.sol";
import "./lib/WeightedPool.sol";
// import "@balancer-labs/pool-weighted/contracts/WeightedPool.sol";
import "@balancer-labs/interfaces/contracts/vault/IVault.sol";
import "./lib/WeightedPoolNoAMFactory.sol";
import "./lib/ReserveToken.sol";

contract WeightedReserveController is BaseWeightedUtils {

    address private constant RESERVE_TOKEN = 0x7d9d314Ee8183653F800e551030d0b27663A1557;

    struct TradeValues {
        IWeightedPool collateral;
        bytes32 poolId;
        int [] tokenPrices;
        uint256 [] normalizedWeights;
        IERC20 [] tokens;
        uint256 [] balances;
        IAsset [] assets;
    }

    address [] private registeredPools;
    mapping(address => bool) private registeredPoolsMapping;

    address internal immutable weightedPoolNoAMFactory;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     * @param supportedWeightedPoolNoAMFactory - ManegedPoolFactory address
     */
    constructor(address vaultAddress, address supportedWeightedPoolNoAMFactory)
    BaseWeightedUtils(vaultAddress) {
        manager = msg.sender;
        weightedPoolNoAMFactory = supportedWeightedPoolNoAMFactory;
    }

    /**
     * @notice returns a list of registered pools
     *
     */
    function getRegisteredPools() public view returns (address [] memory) {
        return registeredPools;
    }

    /**
     * @notice Register weighted pool
     *
     * @param weightedPool - Address of pool being worked on.
     */
    function registerWeightedPool(
        address weightedPool
    ) public restricted {
        registeredPools.push(weightedPool);
        registeredPoolsMapping[weightedPool] = true;
    }

    /**
     * @notice Deregister weighted pool
     *
     * @param weightedPool - Address of pool being worked on.
     */
    function deRegisterWeightedPool(
        address weightedPool
    ) public restricted {
        removeByValue(weightedPool);
        registeredPoolsMapping[weightedPool] = false;
    }

    /**
     * @notice This function is used for pools containing two tokens.
     * It takes in a collateral token such as BPT, calculates an equal
     * value amount of the reserve token such as G$ then mints and returns it.
     *
     * @param tokenIn - Address of collateral token
     * @param amountIn - The amount being traded
     * @param recipient - Address of person to receive the reserve tokens
     */
    function buyReserveToken(
        address tokenIn,
        uint256 amountIn,
        address recipient
    ) public   {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        TradeValues memory tradeValues;
        tradeValues.collateral = IWeightedPool(tokenIn);
        IERC20 collateral = IERC20(tokenIn);

        // Calculate the buyers share of the pool
        uint256 totalSupply = collateral.totalSupply();
        uint256 buyersShare = amountIn / totalSupply;

        tradeValues.poolId = tradeValues.collateral.getPoolId();
        vault.getPool(tradeValues.poolId);
        tradeValues.normalizedWeights = tradeValues
            .collateral
            .getNormalizedWeights();

        (tradeValues.tokens, tradeValues.balances, ) = vault.getPoolTokens(
            tradeValues.poolId
        );
        
        tradeValues.assets = SupportLib._convertERC20sToAssets(
            tradeValues.tokens
        );

        // Calculate token prices using Chainlink. All prices are to 8 decimal places.
        tradeValues.tokenPrices = new int[](tradeValues.tokens.length);
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            if (tradeValues.balances [i] > 0) {
                tradeValues.tokenPrices [i] = getTokenPrice(address(tradeValues.tokens [i]));
            }
            else
            {
                tradeValues.tokenPrices [i] = 0;
            }
        }

        // Calculate the total value of the pool
        uint256 totalPoolValue = 0;
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            totalPoolValue =
                totalPoolValue +
                (tradeValues.balances [i] * uint256(tradeValues.tokenPrices [i]));
        }

        // Calculate supplied token value
        uint256 buyersShareValue = buyersShare * totalPoolValue;
        ReserveToken reserveToken = ReserveToken(
            RESERVE_TOKEN
        );

        require(
            collateral.transferFrom(msg.sender, address(this), amountIn),
            "Transfer of input tokens failed"
        );

        // Mint and Transfer the output tokens from this contract to the recipient, assuming reserve token is worth $1
        reserveToken.mint(recipient, buyersShareValue * (10 ** 18));
    }
    
    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param pool - Address of collateral token
     * @param amountIn - The amount being traded
     * @param recipient - Address of person to receive the swapped tokens
     */
    function sellReserveToken(
        address pool,
        uint256 amountIn,
        address recipient
    ) public nonReentrant checkPoolSupported(pool) {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        TradeValues memory tradeValues;
        tradeValues.collateral = IWeightedPool(pool);
        IERC20 bptToken = IERC20(pool);
        uint256 totalSupply = bptToken.totalSupply();

        tradeValues.poolId = tradeValues.collateral.getPoolId();
        vault.getPool(tradeValues.poolId);
        tradeValues.normalizedWeights = tradeValues
            .collateral
            .getNormalizedWeights();

        (tradeValues.tokens, tradeValues.balances, ) = vault.getPoolTokens(
            tradeValues.poolId
        );
        tradeValues.assets = SupportLib._convertERC20sToAssets(
            tradeValues.tokens
        );

        // Calculate token prices using Chainlink. All prices are to 8 decimal places.
        tradeValues.tokenPrices = new int[](tradeValues.tokens.length);
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            if (tradeValues.balances [i] > 0) {
                tradeValues.tokenPrices [i] = getTokenPrice(address(tradeValues.tokens [i]));
            }
            else
            {
                tradeValues.tokenPrices [i] = 0;
            }
        }

        // Calculate the total value of the pool
        uint256 totalPoolValue = 0;
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            totalPoolValue =
                totalPoolValue +
                (tradeValues.balances [i] * uint256(tradeValues.tokenPrices [i]));
        }

        // Calculate supplied token value
        uint256 myShare = amountIn / totalSupply;
        uint256 myBptAmount = myShare * totalSupply;

        // Transfer the input tokens from the sender to this contract
        IERC20 reserveToken = IERC20(RESERVE_TOKEN);
        require(
            reserveToken.transferFrom(msg.sender, address(this), amountIn),
            "Transfer of input tokens failed"
        );

        // Transfer the output tokens from this contract to the recipient
        bptToken.transfer(recipient, myBptAmount * (10 ** 18));
    }

    /**
     * @notice returns the array index containing supplied address
     *
     * @param value - Address to find
     */
    function find(address value) private view returns (uint) {
        for(uint i = 0; i < registeredPools.length; i++) {
            if(registeredPools[i] == value) {
                return i; 
            }
        }

        return registeredPools.length;
    }

    /**
     * @notice removes supplied address from array of addresses
     *
     * @param value - Address to look up and remove element
     */
    function removeByValue(address value) private {
        registeredPoolsMapping[value] = false;
        uint i = find(value);
        removeByIndex(i);
    }

    /**
     * @notice remove the item at index, resizing array as needed
     *
     * @param i - Index to remove
     */
    function removeByIndex(uint i) private {
        while (i < registeredPools.length - 1) {
            registeredPools [i] = registeredPools [i + 1];
            i++;
        }
        registeredPools.pop();
    }

    /**
     * @dev Modifier to check token allowance
     *
     * @param supportedWeightedPool - Weighted pool address to remove
     */
    modifier checkPoolSupported(address supportedWeightedPool) {
        require(registeredPoolsMapping[supportedWeightedPool], "Pool not registered");
        _;
    }
}
