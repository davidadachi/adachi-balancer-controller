// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./base/BaseUtils.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "./lib/ManagedPoolFactory.sol";
import "./lib/ReserveToken.sol";

contract ReserveController is BaseUtils {

    address private constant RESERVE_TOKEN = 0x98A90EcFB163d138eC289D05362f20613A0C02aC;

    event CreatedPoolByDelegateCall(
        ManagedPoolParams managedPoolParams,
        ManagedPoolSettingsParams managedPoolSettingsParams,
        address callerAddress,
        bytes32 salt,
        bool isSuccessful
    );

    struct TradeValues {
        IManagedPool collateral;
        bytes32 poolId;
        int [] tokenPrices;
        uint256 [] normalizedWeights;
        IERC20 [] tokens;
        uint256 [] balances;
        IAsset [] assets;
    }

    struct JoinPoolRequest {
        IERC20[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    address [] private registeredPools;
    IVault internal immutable vault;
    address internal immutable managedPoolFactory;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     * @param supportedManagedPoolFactory - ManegedPoolFactory address
     */
    constructor(address vaultAddress, address supportedManagedPoolFactory) {
        manager = msg.sender;
        vault = IVault(vaultAddress);
        managedPoolFactory = supportedManagedPoolFactory;
    }

    /**
     * @notice Create and register a new managed pool
     *
     * @param name - Pool name
     * @param symbol - Symbol representing the pool
     * @param tokens - Tokens in the pool
     * @param normalizedWeights - Normalized weights in the pool
     * @param assetManagers - Asset manager for the pool
     * @param swapFeePercentage - Fee applied to swaps
     * @param isSwapEnabledOnStart - Whether swaps are enabled straight away
     * @param isMustAllowlistLPs - List of LP's allowed in the pool
     * @param managementAumFeePercentage - Management Aum fee to apply
     * @param aumFeeId - Aum Fee Id
     * @param salt - Salt applied to address to ensure uniqueness
     */
    function createPool(
        string memory name,
        string memory symbol,
        IERC20 [] memory tokens,
        uint256 [] memory normalizedWeights,
        address [] memory assetManagers,
        uint256 swapFeePercentage,
        bool isSwapEnabledOnStart,
        bool isMustAllowlistLPs,
        uint256 managementAumFeePercentage,
        uint256 aumFeeId,
        bytes32 salt
    ) public{
        ManagedPoolParams memory poolParams;
        poolParams.name = name;
        poolParams.symbol = symbol;
        poolParams.assetManagers = assetManagers;

        ManagedPoolSettingsParams memory poolSettingsParams;
        poolSettingsParams.tokens = tokens;
        poolSettingsParams.normalizedWeights = normalizedWeights;
        poolSettingsParams.swapFeePercentage = swapFeePercentage;
        poolSettingsParams.isSwapEnabledOnStart = isSwapEnabledOnStart;
        poolSettingsParams.isMustAllowlistLPs = isMustAllowlistLPs;
        poolSettingsParams
            .managementAumFeePercentage = managementAumFeePercentage;
        poolSettingsParams.aumFeeId = aumFeeId;

        (bool isSuccessful, bytes memory result) = managedPoolFactory.delegatecall(
            abi.encodeWithSelector(
                ManagedPoolFactory.create.selector,
                poolParams,
                poolSettingsParams,
                msg.sender,
                salt
            )
        );

        emit CreatedPoolByDelegateCall(
            poolParams,
            poolSettingsParams,
            msg.sender,
            salt,
            isSuccessful
        );
        if (isSuccessful) {
            address poolAddress = abi.decode(result, (address));
            registerManagedPool(poolAddress);
        }
    }

    /**
     * @notice returns a list of registered pools
     *
     */
    function getRegisteredPools() public view returns (address [] memory) {
        return registeredPools;
    }

    /**
     * @notice Register managed pool
     *
     * @param managedPool - Address of pool being worked on.
     */
    function registerManagedPool(
        address managedPool
    ) public restricted {
        registeredPools.push(managedPool);
    }

    /**
     * @notice Deregister managed pool
     *
     * @param managedPool - Address of pool being worked on.
     */
    function deRegisterManagedPool(
        address managedPool
    ) public restricted {
        removeByValue(managedPool);
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
    ) public nonReentrant checkPoolSupported(tokenIn) {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        TradeValues memory tradeValues;
        tradeValues.collateral = IManagedPool(tokenIn);
        IERC20 collateral = IERC20(tokenIn);

        // Transfer the input tokens from the sender to this contract
        require(
            collateral.transferFrom(msg.sender, address(this), amountIn),
            "Transfer of input tokens failed"
        );

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
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            if (tradeValues.balances [i] > 0) {
                tradeValues.tokenPrices [i] = getTokenPrice(address(tradeValues.tokens [i]));
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

        // Mint and Transfer the output tokens from this contract to the recipient, assuming reserve token is worth $1
        reserveToken.mint(recipient, buyersShareValue * (10 ** 18));
    }
    
    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param tokenIn - Address of reserve token
     * @param pool - Address of collateral token
     * @param amountIn - The amount being traded
     * @param recipient - Address of person to receive the swapped tokens
     */
    function sellReserveToken(
        address tokenIn,
        address pool,
        uint256 amountIn,
        address recipient
    ) public nonReentrant checkPoolSupported(pool) {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        TradeValues memory tradeValues;
        tradeValues.collateral = IManagedPool(pool);
        IERC20 bptToken = IERC20(pool);
        uint256 totalSupply = bptToken.totalSupply();

        // Transfer the input tokens from the sender to this contract
        IERC20 collateralToken = IERC20(tokenIn);
        require(
            collateralToken.transferFrom(msg.sender, address(this), amountIn),
            "Transfer of input tokens failed"
        );

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
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            if (tradeValues.balances [i] > 0) {
                tradeValues.tokenPrices [i] = getTokenPrice(address(tradeValues.tokens [i]));
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

        // Transfer the output tokens from this contract to the recipient
        bptToken.transfer(recipient, myBptAmount * (10 ** 18));
    }

    /**
     * @notice returns the array index containing supplied address
     *
     * @param value - Address to find
     */
    function find(address value) private view returns (uint) {
        uint i = 0;
        while (registeredPools [i] != value) {
            i++;
        }
        return i;
    }

    /**
     * @notice removes supplied address from array of addresses
     *
     * @param value - Address to look up and remove element
     */
    function removeByValue(address value) private {
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
     * @param supportedManagedPool - Managed pool address to remove
     */
    modifier checkPoolSupported(address supportedManagedPool) {
        require(find(supportedManagedPool) != 0, "Pool not registered");
        _;
    }
}
