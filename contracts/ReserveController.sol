// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "./base/BaseUtils.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "./lib/ManagedPoolFactory.sol";
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "./lib/ReserveToken.sol";

contract ReserveController is ReentrancyGuard, BaseUtils {

    event CreatedPoolByDelegateCall(ManagedPoolParams managedPoolParams, ManagedPoolSettingsParams managedPoolSettingsParams, address callerAddress, bytes32 salt, bool success);

    struct TradeValues {
        IManagedPool collateral;
        bytes32 poolId;
        uint256 tokenPrice;
        uint256[] tokenPrices;
        uint256[] normalizedWeights;
        IERC20[] tokens;
        uint256[] balances;
        IAsset[] assets;
    }

    address[] private registeredPools;
    IVault internal immutable vault;
    address internal immutable managedPoolFactory;

    /**
     * @notice Constructor for the controller base class
     *
     * @param _vaultAddress - Vault contract address
     * @param _managedPoolFactory - ManegedPoolFactory address
     */
    constructor(address _vaultAddress,
                address _managedPoolFactory) {
        manager = msg.sender;
        vault = IVault(_vaultAddress);
        managedPoolFactory = _managedPoolFactory;
    }

    /**
     * @notice Create and register a new managed pool
     *
     * @param _name - Pool name
     * @param _symbol - Symbol representing the pool
     * @param _tokens - Tokens in the pool
     * @param _normalizedWeights - Normalized weights in the pool
     * @param _assetManagers - Asset manager for the pool
     * @param _swapFeePercentage - Fee applied to swaps
     * @param _swapEnabledOnStart - Whether swaps are enabled straight away
     * @param _mustAllowlistLPs - List of LP's allowed in the pool
     * @param _managementAumFeePercentage - Management Aum fee to apply
     * @param _aumFeeId - Aum Fee Id
     * @param _salt - Salt applied to address to ensure uniqueness
     */
    function createPool(string memory _name,
                        string memory _symbol,
                        IERC20[] memory _tokens,
                        uint256[] memory _normalizedWeights,
                        address[] memory _assetManagers,
                        uint256 _swapFeePercentage,
                        bool _swapEnabledOnStart,
                        bool _mustAllowlistLPs,
                        uint256 _managementAumFeePercentage,
                        uint256 _aumFeeId,
                        bytes32 _salt) public {
        ManagedPoolParams memory poolParams;
        poolParams.name = _name;
        poolParams.symbol = _symbol;
        poolParams.assetManagers = _assetManagers;

        ManagedPoolSettingsParams memory poolSettingsParams;
        poolSettingsParams.tokens = _tokens;
        poolSettingsParams.normalizedWeights = _normalizedWeights;
        poolSettingsParams.swapFeePercentage = _swapFeePercentage;
        poolSettingsParams.swapEnabledOnStart = _swapEnabledOnStart;
        poolSettingsParams.mustAllowlistLPs = _mustAllowlistLPs;
        poolSettingsParams.managementAumFeePercentage = _managementAumFeePercentage;
        poolSettingsParams.aumFeeId = _aumFeeId;

        (bool success, bytes memory result) = managedPoolFactory.delegatecall(
            abi.encodeWithSelector(ManagedPoolFactory.create.selector, poolParams, poolSettingsParams, msg.sender, _salt)
        );

        emit CreatedPoolByDelegateCall(poolParams, poolSettingsParams, msg.sender, _salt, success);
        if (success)
        {
            address poolAddress = abi.decode(result, (address));
            registerManagedPool(poolAddress);
        }
    }

    /**
     * @notice returns a list of registered pools
     *
     */
    function getRegisteredPools() public view returns (address[] memory) {
        return registeredPools;
    }

    /**
     * @notice Register managed pool
     *
     * @param _managedPool - Address of pool being worked on.
     */
    function registerManagedPool(address _managedPool) public restricted nonReentrant {
        registeredPools.push(_managedPool);
    }

    /**
     * @notice Deregister managed pool
     *
     * @param _managedPool - Address of pool being worked on.
     */
    function deRegisterManagedPool(address _managedPool) public restricted nonReentrant {
        removeByValue(_managedPool);
    }

    /**
     * @notice This function is used for pools containing two tokens.
     * It takes in a collateral token such as BPT, calculates an equal
     * value amount of the reserve token such as G$ then mints and returns it.
     *
     * @param _tokenIn - Address of collateral token
     * @param _amountIn - The amount being traded
     * @param _recipient - Address of person to receive the reserve tokens
     */
    function buyReserveToken(address  _tokenIn,
                             uint256 _amountIn,
                             address _recipient) public nonReentrant checkPoolSupported(_tokenIn)
    {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        TradeValues memory tradeValues;
        tradeValues.collateral = IManagedPool(_tokenIn);
        IERC20 collateral = IERC20(_tokenIn);

        // Transfer the input tokens from the sender to this contract
        require(collateral.transferFrom(msg.sender, address(this), _amountIn), "Transfer of input tokens failed");

        // Calculate the buyers share of the pool
        uint256 totalSupply = collateral.totalSupply();
        uint256 buyersShare = _amountIn / totalSupply;

        tradeValues.poolId = tradeValues.collateral.getPoolId();
        vault.getPool(tradeValues.poolId);
        tradeValues.normalizedWeights = tradeValues.collateral.getNormalizedWeights();

        (tradeValues.tokens, tradeValues.balances,) = vault.getPoolTokens(tradeValues.poolId);
        tradeValues.assets = SupportLib._convertERC20sToAssets(tradeValues.tokens);

        // Calculate token prices using the DEX
        if (tradeValues.balances[0]  > 0)
        {
            tradeValues.tokenPrices[0] = (tradeValues.balances[1] / tradeValues.normalizedWeights[1]) / (tradeValues.balances[0] / tradeValues.normalizedWeights[0]);
        }

        for (uint256 i = 1; i < tradeValues.tokens.length; i++) {
            if (tradeValues.balances[i] > 0)
            {
                tradeValues.tokenPrices[i] = (tradeValues.balances[0] / tradeValues.normalizedWeights[0]) / (tradeValues.balances[i] / tradeValues.normalizedWeights[i]);
            }
        }

        // Calculate the total value of the pool
        uint256 totalPoolValue = 0;
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            totalPoolValue = totalPoolValue + (tradeValues.balances[i] * tradeValues.tokenPrices[i]);
        }

        // Calculate supplied token value
        uint256 buyersShareValue = buyersShare * totalPoolValue;
        ReserveToken reserveToken = ReserveToken(0x785fA6c4383c42deF4182C1820D23f1196a112CE);

        // Mint and Transfer the output tokens from this contract to the recipient, assuming reserve token is worth $1
        reserveToken.mint(_recipient, buyersShareValue * (10 ** 18));
    }

    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param _tokenIn - Address of reserve token
     * @param _pool - Address of collateral token
     * @param _amountIn - The amount being traded
     * @param _recipient - Address of person to receive the swapped tokens
     */
    function sellReserveToken(address _tokenIn,
                              address _pool,
                              uint256 _amountIn,
                              address _recipient) public nonReentrant checkPoolSupported(_pool)
    {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        TradeValues memory tradeValues;
        tradeValues.collateral = IManagedPool(_pool);
        IERC20 bptToken = IERC20(_pool);
        uint256 totalSupply = bptToken.totalSupply();

        // Transfer the input tokens from the sender to this contract
        IERC20 collateralToken = IERC20(_tokenIn);
        require(collateralToken.transferFrom(msg.sender, address(this), _amountIn), "Transfer of input tokens failed");

        tradeValues.poolId = tradeValues.collateral.getPoolId();
        vault.getPool(tradeValues.poolId);
        tradeValues.normalizedWeights = tradeValues.collateral.getNormalizedWeights();

        (tradeValues.tokens, tradeValues.balances,) = vault.getPoolTokens(tradeValues.poolId);
        tradeValues.assets = SupportLib._convertERC20sToAssets(tradeValues.tokens);

        // Calculate token prices using the DEX
        if (tradeValues.balances[0]  > 0)
        {
            tradeValues.tokenPrices[0] = (tradeValues.balances[1] / tradeValues.normalizedWeights[1]) / (tradeValues.balances[0] / tradeValues.normalizedWeights[0]);
        }

        for (uint256 i = 1; i < tradeValues.tokens.length; i++) {
            tradeValues.tokenPrice = 0;
            if (tradeValues.balances[i] > 0)
            {
                tradeValues.tokenPrices[1] = (tradeValues.balances[0] / tradeValues.normalizedWeights[0]) / (tradeValues.balances[i] / tradeValues.normalizedWeights[i]);
            }
        }

        // Calculate the total value of the pool
        uint256 totalPoolValue = 0;
        for (uint256 i = 0; i < tradeValues.tokens.length; i++) {
            totalPoolValue = totalPoolValue + (tradeValues.balances[i] * tradeValues.tokenPrices[i]);
        }

        // Calculate supplied token value
        uint256 myShare = _amountIn / totalSupply;
        uint256 myBptAmount = myShare * totalSupply;

        // Transfer the output tokens from this contract to the recipient
        bptToken.transfer(_recipient, myBptAmount * (10 ** 18));
    }

    /**
     * @notice returns the array index containing supplied address
     *
     * @param value - Address to find
     */
    function find(address value) private view returns(uint) {
        uint i = 0;
        while (registeredPools[i] != value) {
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
        while (i < registeredPools.length-1) {
            registeredPools[i] = registeredPools[i+1];
            i++;
        }
        registeredPools.pop();
    }

    /**
     * @dev Modifier to check token allowance
     *
     * @param _managedPool - Managed pool address to remove
     */
    modifier checkPoolSupported(address _managedPool) {
        require(find(_managedPool) != 0, "Pool not registered");
        _;
    }
}
