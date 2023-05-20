// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
//import "@balancer-labs/v2-pool-weighted/contracts/managed/ManagedPoolFactory.sol";
import "../ManagedPoolFactory.sol";

struct PoolPrice {
    address token;
    uint256 price;
}

struct PoolSettings {
    bool activelyManaged;
    mapping(address => PoolPrice) prices;
}

abstract contract BaseController is ReentrancyGuard {
    address public manager;
    IVault internal immutable vault;
    ManagedPoolFactory public immutable managedPoolFactory;
    mapping(address => PoolSettings) internal managedPools; // Pools and their prices
    address[] private poolsUnderManagement;

     /**
     * @notice Constructor for the controller base class
     *
     * @param _vaultAddress - Vault contract address
     * @param _managedPoolFactory - Managed pool contract address
     */
    constructor(address _vaultAddress, 
                address _managedPoolFactory) {
        manager = msg.sender;
        vault = IVault(_vaultAddress);
        managedPoolFactory = ManagedPoolFactory(_managedPoolFactory);
    }

     /**
     * @notice Create a new managed pool
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
                        bytes32 salt) public restricted nonReentrant {
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

        address _poolAddress = managedPoolFactory.create(poolParams, poolSettingsParams, address(this), salt);
        poolsUnderManagement.push(_poolAddress);
        managedPools[_poolAddress].activelyManaged = true;
    }

    /**
     * @notice returns a list of pools under management by this controller
     *
     */
    function getPoolsUnderManagement() public view returns (address[] memory) {
        return poolsUnderManagement;
    }

    /**
     * @notice Returns the pools Id
     *
     * @param _poolAddress - Pool to get the Id for
     */
    function getPoolId(address _poolAddress) public view returns (bytes32) {
        CurveValues memory curveInfo;
        curveInfo.managedPool = IManagedPool(_poolAddress);
        curveInfo.poolId = curveInfo.managedPool.getPoolId();
    //    curveInfo.name = curveInfo.managedPool.name();
    //    curveInfo.symbol = curveInfo.managedPool.symbol();
        return curveInfo.poolId;
    }

    /**
     * @notice Set target prices used for balancing
     *
     * @param _pool - Pool to have prices set.
     * @param _tokens - The collection of tokens to have prices set
     * @param _prices - The collection of prices to set
     */
    function setTargetPoolPrices(address _pool,
                                 address[] memory _tokens,
                                 uint256[] memory _prices) public restricted {
        for (uint256 count = 0; count < _tokens.length; count++) {

            managedPools[_pool].prices[_tokens[count]].token = _tokens[count];
            managedPools[_pool].prices[_tokens[count]].price = _prices[count];
        }
    }

    /**
     * @notice Transfer the manager to a new address
     * @dev Only one manager can presently be set
     *
     * @param _manager - New manager.
     */
    function transferManagement(address _manager) public restricted {
        manager = _manager;
    }
    
    /**
     * @notice Schedule a gradual swap fee update.
     * @dev The swap fee will change from the given starting value (which may or may not be the current
     * value) to the given ending fee percentage, over startTime to endTime.
     *
     * Note that calling this with a starting swap fee different from the current value will immediately change the
     * current swap fee to `startSwapFeePercentage`, before commencing the gradual change at `startTime`.
     * Emits the GradualSwapFeeUpdateScheduled event.
     * This is a permissioned function.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _startTime - The timestamp when the swap fee change will begin.
     * @param _endTime - The timestamp when the swap fee change will end (must be >= startTime).
     * @param _startSwapFeePercentage - The starting value for the swap fee change.
     * @param _endSwapFeePercentage - The ending value for the swap fee change. If the current timestamp >= endTime,
     * `getSwapFeePercentage()` will return this value.
     */
    function updateSwapFeeGradually(
        address _poolAddress,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _startSwapFeePercentage,
        uint256 _endSwapFeePercentage) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.updateSwapFeeGradually(_startTime, _endTime, _startSwapFeePercentage, _endSwapFeePercentage);
    }

    /**
     * @notice Schedule a gradual weight change.
     * @dev The weights will change from their current values to the given endWeights, over startTime to endTime.
     * This is a permissioned function.
     *
     * Since, unlike with swap fee updates, we generally do not want to allow instantaneous weight changes,
     * the weights always start from their current values. This also guarantees a smooth transition when
     * updateWeightsGradually is called during an ongoing weight change.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _startTime - The timestamp when the weight change will begin.
     * @param _endTime - The timestamp when the weight change will end (can be >= startTime).
     * @param _tokens - The tokens associated with the target weights (must match the current pool tokens).
     * @param _endWeights - The target weights. If the current timestamp >= endTime, `getNormalizedWeights()`
     * will return these values.
     */
    function updateWeightsGradually(
        address _poolAddress,
        uint256 _startTime,
        uint256 _endTime,
        IERC20[] memory _tokens,
        uint256[] memory _endWeights) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.updateWeightsGradually(_startTime, _endTime, _tokens, _endWeights);
    }

    /**
     * @notice Enable or disable joins and exits. Note that this does not affect Recovery Mode exits.
     * @dev Emits the JoinExitEnabledSet event. This is a permissioned function.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _joinExitEnabled - The new value of the join/exit enabled flag.
     */
    function setJoinExitEnabled(
        address _poolAddress,
        bool _joinExitEnabled) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.setJoinExitEnabled(_joinExitEnabled);
    }

    /**
     * @notice Enable or disable trading.
     * @dev Emits the SwapEnabledSet event. This is a permissioned function.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _swapEnabled - The new value of the swap enabled flag.
     */
    function setSwapEnabled(
        address _poolAddress,
        bool _swapEnabled) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.setSwapEnabled(_swapEnabled);
    }

    /**
     * @notice Enable or disable the LP allowlist.
     * @dev Note that any addresses added to the allowlist will be retained if the allowlist is toggled off and
     * back on again, because this action does not affect the list of LP addresses.
     * Emits the MustAllowlistLPsSet event. This is a permissioned function.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _mustAllowlistLPs - The new value of the mustAllowlistLPs flag.
     */
    function setMustAllowlistLPs(
        address _poolAddress,
        bool _mustAllowlistLPs) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.setMustAllowlistLPs(_mustAllowlistLPs);
    }

    /**
     * @notice Adds an address to the LP allowlist.
     * @dev Will fail if the address is already allowlisted.
     * Emits the AllowlistAddressAdded event. This is a permissioned function.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _member - The address to be added to the allowlist.
     */
    function addAllowedAddress(
        address _poolAddress,
        address _member) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.addAllowedAddress(_member);
    }

    /**
     * @notice Removes an address from the _poolAddress - Address of pool being worked on.
     *
     * @param _poolAddress - Pool address being worked on
     * @param _member - The address to be removed from the allowlist.
     */
    function removeAllowedAddress(
        address _poolAddress,
        address _member) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.removeAllowedAddress(_member);
    }

    /**
     * @notice Collect any accrued AUM fees and send them to the pool manager.
     * @dev This can be called by anyone to collect accrued AUM fees - and will be called automatically
     * whenever the supply changes (e.g., joins and exits, add and remove token), and before the fee
     * percentage is changed by the manager, to prevent fees from being applied retroactively.
     *
     * @param _poolAddress - Address of pool being worked on.
     */
    function collectAumManagementFees(
        address _poolAddress) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.collectAumManagementFees();
    }
    
    /**
     * @notice Setter for the yearly percentage AUM management fee, which is payable to the pool manager.
     * @dev Attempting to collect AUM fees in excess of the maximum permitted percentage will revert.
     * To avoid retroactive fee increases, we force collection at the current fee percentage before processing
     * the update. Emits the ManagementAumFeePercentageChanged event. This is a permissioned function.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _managementAumFeePercentage - The new management AUM fee percentage.
     */
    function setManagementAumFeePercentage(
        address _poolAddress,
        uint256 _managementAumFeePercentage) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.setManagementAumFeePercentage(_managementAumFeePercentage);
    }

    /**
     * @notice Set a circuit breaker for one or more tokens.
     * @dev This is a permissioned function. The lower and upper bounds are percentages, corresponding to a
     * relative change in the token's spot price: e.g., a lower bound of 0.8 means the breaker should prevent
     * trades that result in the value of the token dropping 20% or more relative to the rest of the pool.
     *
     * @param _poolAddress - Pool to have a circruit breaker set
     * @param _tokens - Tokens in the pool
     * @param _bptPrices - Token prices to for the circuit breaker
     * @param _lowerBoundPercentages - The lower limit to trigger the circuit breaker
     * @param _upperBoundPercentages - The upper limit to trigger the circuit breaker
     */
    function setCircuitBreakers(
        address _poolAddress,
        IERC20[] memory _tokens,
        uint256[] memory _bptPrices,
        uint256[] memory _lowerBoundPercentages,
        uint256[] memory _upperBoundPercentages) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.setCircuitBreakers(_tokens, _bptPrices, _lowerBoundPercentages, _upperBoundPercentages);
    }

    /**
     * @notice Adds a token to the Pool's list of tradeable tokens. This is a permissioned function.
     *
     * @dev By adding a token to the Pool's composition, the weights of all other tokens will be decreased. The new
     * token will have no balance - it is up to the owner to provide some immediately after calling this function.
     * Note however that regular join functions will not work while the new token has no balance: the only way to
     * deposit an initial amount is by using an Asset Manager.
     *
     * Token addition is forbidden during a weight change, or if one is scheduled to happen in the future.
     *
     * The caller may additionally pass a non-zero `mintAmount` to have some BPT be minted for them, which might be
     * useful in some scenarios to account for the fact that the Pool will have more tokens.
     *
     * Emits the TokenAdded event.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _tokenToAdd - The ERC20 token to be added to the Pool.
     * @param _assetManager - The Asset Manager for the token.
     * @param _tokenToAddNormalizedWeight - The normalized weight of `token` relative to the other tokens in the Pool.
     * @param _mintAmount - The amount of BPT to be minted as a result of adding `token` to the Pool.
     * @param _recipient - The address to receive the BPT minted by the Pool.
     */
    function addToken(
        address _poolAddress,
        IERC20 _tokenToAdd,
        address _assetManager,
        uint256 _tokenToAddNormalizedWeight,
        uint256 _mintAmount,
        address _recipient) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.addToken(_tokenToAdd, _assetManager, _tokenToAddNormalizedWeight, _mintAmount, _recipient);
    }

    /**
     * @notice Removes a token from the Pool's list of tradeable tokens.
     * @dev Tokens can only be removed if the Pool has more than 2 tokens, as it can never have fewer than 2 (not
     * including BPT). Token removal is also forbidden during a weight change, or if one is scheduled to happen in
     * the future.
     *
     * Emits the TokenRemoved event. This is a permissioned function.
     *
     * The caller may additionally pass a non-zero `burnAmount` to burn some of their BPT, which might be useful
     * in some scenarios to account for the fact that the Pool now has fewer tokens. This is a permissioned function.
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _tokenToRemove - The ERC20 token to be removed from the Pool.
     * @param _burnAmount - The amount of BPT to be burned after removing `token` from the Pool.
     * @param _sender - The address to burn BPT from.
     */
    function removeToken(
        address _poolAddress,
        IERC20 _tokenToRemove,
        uint256 _burnAmount,
        address _sender) public restricted nonReentrant {

        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        managedPool.removeToken(_tokenToRemove, _burnAmount, _sender);
    }

    /**
     * @notice Withdraw tokens from controller
     * @dev Transfers an amount of an ERC20 token
     *
     * @param _recipientAddress - Address of wallet receiving funds.
     * @param _tokenAddress - Address of token to be withdrawn.
     * @param _amount - Amount to withdraw.
     */
    function withdrawFunds(
        address _recipientAddress,
        address _tokenAddress,
        uint256 _amount) public restricted nonReentrant {

        IERC20 _token = IERC20(_tokenAddress);
        _token.transferFrom(address(this), _recipientAddress, _amount);
    }

    /**
     * @notice Deposit tokens to controller
     * @dev Transfers an amount of an ERC20 token
     *
     * @param _amount - Amount to deposit.
     * @param _tokenAddress - Address of token to be deposited.
     */
    function depositTokens(
        uint _amount,
        address _tokenAddress) public restricted nonReentrant checkAllowance(_amount, _tokenAddress) {
        IERC20 token = IERC20(_tokenAddress);
        token.transferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @dev This helper function is a fast and cheap way to convert between IERC20 and IAsset types
     *
     * @param _tokens - Tokens to convert to assets
     */
    function _convertERC20sToAssets(IERC20[] memory _tokens) internal pure returns (IAsset[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := _tokens
        }
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
     */
    modifier checkAllowance(uint _amount,
                            address _tokenAddress) {
        IERC20 token = IERC20(_tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= _amount, "Error");
        _;
    }
}
