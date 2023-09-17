// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../lib/WeightedPoolNoAMFactory.sol";
import "./BaseWeightedUtils.sol";

abstract contract BaseWeightedController is BaseWeightedUtils {
    WeightedPoolNoAMFactory public immutable weightedPoolFactory;
    address [] private _poolsUnderManagement;

    /**
     * @notice Constructor for the controller base class
     *
     * @param vaultAddress - Vault contract address
     * @param supportedWeightedPoolFactory - Weighted pool contract address
     */
    constructor(address vaultAddress, address supportedWeightedPoolFactory)
        BaseWeightedUtils(vaultAddress) {
            manager = msg.sender;
            weightedPoolFactory = WeightedPoolNoAMFactory(supportedWeightedPoolFactory);
    }

    /**
     * @notice Create a new weighted pool
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
     * @param tolerance - Percentage devience 
     * @param salt - Salt used towards calculating pool address
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
        uint256 tolerance,
        bytes32 salt
    ) public restricted nonReentrant {
        WeightedPoolParams memory poolParams;
        poolParams.name = name;
        poolParams.symbol = symbol;
        poolParams.assetManagers = assetManagers;

        WeightedPoolSettingsParams memory poolSettingsParams;
        poolSettingsParams.tokens = tokens;
        poolSettingsParams.normalizedWeights = normalizedWeights;
        poolSettingsParams.swapFeePercentage = swapFeePercentage;
        poolSettingsParams.isSwapEnabledOnStart = isSwapEnabledOnStart;
        poolSettingsParams.isMustAllowlistLPs = isMustAllowlistLPs;
        poolSettingsParams
            .managementAumFeePercentage = managementAumFeePercentage;
        poolSettingsParams.aumFeeId = aumFeeId;

        address poolAddress = weightedPoolFactory.create(
            poolParams,
            poolSettingsParams,
            address(this),
            salt
        );
        _poolsUnderManagement.push(poolAddress);

        weightedPools [poolAddress].poolName = name;
        weightedPools [poolAddress].poolSymbol = symbol;
        weightedPools [poolAddress].tolerance = tolerance;
        weightedPools [poolAddress].poolTokens = tokens;
    }

    /**
     * @notice returns a list of pools under management by this controller
     *
     */
    function getPoolsUnderManagement() public view returns (address [] memory) {
        return _poolsUnderManagement;
    }

    /**
     * @notice Returns the pools Id
     *
     * @param poolAddress - Pool to get the Id for
     */
    function getPoolId(address poolAddress) public view returns (bytes32) {
        return IWeightedPool(poolAddress).getPoolId();
    }

    /**
     * @notice Withdraw tokens from controller
     * @dev Transfers an amount of an ERC20 token
     *
     * @param recipientAddress - Address of wallet receiving funds.
     * @param tokenAddress - Address of token to be withdrawn.
     * @param amount - Amount to withdraw.
     */
    function withdrawFunds(
        address recipientAddress,
        address tokenAddress,
        uint256 amount
    ) public restricted nonReentrant {
        IERC20 _token = IERC20(tokenAddress);
        _token.transferFrom(address(this), recipientAddress, amount);
    }

    /**
     * @notice Deposit tokens to controller
     * @dev Transfers an amount of an ERC20 token
     *
     * @param amount - Amount to deposit.
     * @param tokenAddress - Address of token to be deposited.
     */
    function depositTokens(
        uint amount,
        address tokenAddress
    ) public restricted nonReentrant checkAllowance(amount, tokenAddress) {
        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), amount);
    }
}
