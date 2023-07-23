// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./base/BaseUtils.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "./lib/ManagedPoolFactory.sol";
import "./lib/ReserveToken.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
        uint256 tokenPrice;
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
    ) public {
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
     * @notice Create and register a new managed pool
     *
     * @param poolId - Pool identifier
     * @param sender - Sender address
     * @param recipient - Recipient address
     * @param assets - Assets being transferred in
     * @param maxAmountsIn - Amount being transferred in
     * @param userData - Encoded user data
     * @param fromInternalBalance - Is this transferred from internal balance?
     */
    function JoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        IERC20[] memory assets,
        uint256[] memory maxAmountsIn,
        bytes memory userData,
        bool fromInternalBalance
    ) public payable returns (bytes memory) {
        JoinPoolRequest memory joinPoolRequest;
        joinPoolRequest.assets = assets;
        joinPoolRequest.maxAmountsIn = maxAmountsIn;
        joinPoolRequest.userData = userData;
        joinPoolRequest.fromInternalBalance = fromInternalBalance;

        (bool isSuccessful, bytes memory returndata) = address(vault).delegatecall(
            abi.encodeWithSelector(
                vault.joinPool.selector,
                poolId,
                sender,
                recipient,
                joinPoolRequest
            )
        );

        if (isSuccessful) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(isSuccessful)
                    revert(add(32, isSuccessful), returndata_size)
                }
            } else {
                revert("joinPool failed");
            }
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
    ) public checkPoolSupported(tokenIn) {
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
    ) public checkPoolSupported(pool) {
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
