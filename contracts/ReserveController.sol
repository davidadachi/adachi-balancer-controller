// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-utils/IManagedPool.sol";
import "./base/BaseUtils.sol";

contract ReserveController is ReentrancyGuard, BaseUtils {

    struct ReserveValues {
        IManagedPool managedPool;
        bytes32 poolId;
        uint256 tokenPrice;
        uint256[] tokenPrices;
        uint256[] normalizedWeights;
        IERC20[] tokens;
        uint256[] balances;
        IAsset[] assets;
    }

    // poolAddress mapped to reserve token
    mapping(address => address) pools;

    IVault internal immutable vault;

    /**
     * @notice Constructor for the controller base class
     *
     * @param _vaultAddress - Vault contract address
     */
    constructor(address _vaultAddress) {
        manager = msg.sender;
        vault = IVault(_vaultAddress);
    }

    /**
     * @notice Register managed pool
     *
     * @param _managedPool - Address of pool being worked on.
     * @param _reserveToken - Address of pool being worked on.
     */
    function registerManagedPool(
        address _managedPool,
        address _reserveToken) public restricted nonReentrant {
        pools[_managedPool] = _reserveToken;
    }

    /**
     * @notice Deregister managed pool
     *
     * @param _managedPool - Address of pool being worked on.
     */
    function deRegisterManagedPool(
        address _managedPool) public restricted nonReentrant {
        delete pools[_managedPool];
    }

    /**
     * @notice This function is used for pools containing two tokensRuns a check
      and transfers reserve tokens as needed
     *
     * @param _tokenIn - Address of collateral token
     * @param _amountIn - The amount being traded
     * @param _recipient - Address of person to receive the swapped tokens
     */
    function buyReserveToken(address  _tokenIn,
                             uint256 _amountIn,
                             address _recipient) public nonReentrant checkPoolSupported(_tokenIn)
    {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        ReserveValues memory reserveValues;
        reserveValues.managedPool = IManagedPool(_tokenIn);
        IERC20 bptToken = IERC20(_tokenIn);

        // Transfer the input tokens from the sender to this contract
        require(bptToken.transferFrom(msg.sender, address(this), _amountIn), "Transfer of input tokens failed");

        // Calculate the buyers share of the pool
        uint256 totalSupply = bptToken.totalSupply();
        uint256 myShare = _amountIn / totalSupply;

        reserveValues.poolId = reserveValues.managedPool.getPoolId();
        vault.getPool(reserveValues.poolId);
        reserveValues.normalizedWeights = reserveValues.managedPool.getNormalizedWeights();

        (reserveValues.tokens, reserveValues.balances,) = vault.getPoolTokens(reserveValues.poolId);
        reserveValues.assets = SupportLib._convertERC20sToAssets(reserveValues.tokens);

        // Calculate token prices using the DEX
        if (reserveValues.balances[0]  > 0)
        {
            reserveValues.tokenPrices[0] = (reserveValues.balances[1] / reserveValues.normalizedWeights[1]) / (reserveValues.balances[0] / reserveValues.normalizedWeights[0]);
        }

        for (uint256 i = 1; i < reserveValues.tokens.length; i++) {
            reserveValues.tokenPrice = 0;
            if (reserveValues.balances[i] > 0)
            {
                reserveValues.tokenPrices[1] = (reserveValues.balances[0] / reserveValues.normalizedWeights[0]) / (reserveValues.balances[i] / reserveValues.normalizedWeights[i]);
            }
        }

        // Calculate the total value of the pool
        uint256 totalPoolValue = 0;
        for (uint256 i = 0; i < reserveValues.tokens.length; i++) {
            totalPoolValue = totalPoolValue + (reserveValues.balances[i] * reserveValues.tokenPrices[i]);
        }

        // Calculate supplied token value
        uint256 myShareValue = myShare * totalPoolValue;

        IERC20 reserveToken = IERC20(pools[_tokenIn]);

        // Transfer the output tokens from this contract to the recipient
        require(reserveToken.transfer(_recipient, myShareValue), "Transfer of output tokens failed");
    }

    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param _tokenIn - Address of reserve token
     * @param _amountIn - The amount being traded
     * @param _recipient - Address of person to receive the swapped tokens
     */
    function sellReserveToken(address _tokenIn,
                              address _pool,
                              uint256 _amountIn,
                              address _recipient) public nonReentrant checkPoolSupported(_tokenIn)
    {
        // Retrieve a list of tokens, balances and normalised weights for the pool
        ReserveValues memory reserveValues;
        reserveValues.managedPool = IManagedPool(_pool);
        IERC20 bptToken = IERC20(_pool);
        uint256 totalSupply = bptToken.totalSupply();

        // Transfer the input tokens from the sender to this contract
        IERC20 collateralToken = IERC20(_tokenIn);
        require(collateralToken.transferFrom(msg.sender, address(this), _amountIn), "Transfer of input tokens failed");

        reserveValues.poolId = reserveValues.managedPool.getPoolId();
        vault.getPool(reserveValues.poolId);
        reserveValues.normalizedWeights = reserveValues.managedPool.getNormalizedWeights();

        (reserveValues.tokens, reserveValues.balances,) = vault.getPoolTokens(reserveValues.poolId);
        reserveValues.assets = SupportLib._convertERC20sToAssets(reserveValues.tokens);

        // Calculate token prices using the DEX
        if (reserveValues.balances[0]  > 0)
        {
            reserveValues.tokenPrices[0] = (reserveValues.balances[1] / reserveValues.normalizedWeights[1]) / (reserveValues.balances[0] / reserveValues.normalizedWeights[0]);
        }

        for (uint256 i = 1; i < reserveValues.tokens.length; i++) {
            reserveValues.tokenPrice = 0;
            if (reserveValues.balances[i] > 0)
            {
                reserveValues.tokenPrices[1] = (reserveValues.balances[0] / reserveValues.normalizedWeights[0]) / (reserveValues.balances[i] / reserveValues.normalizedWeights[i]);
            }
        }

        // Calculate the total value of the pool
        uint256 totalPoolValue = 0;
        for (uint256 i = 0; i < reserveValues.tokens.length; i++) {
            totalPoolValue = totalPoolValue + (reserveValues.balances[i] * reserveValues.tokenPrices[i]);
        }

        // Calculate supplied token value
        uint256 myShare = _amountIn / totalSupply;
        uint256 myBptAmount = myShare * totalSupply;

        // Transfer the output tokens from this contract to the recipient
        require(bptToken.transfer(_recipient, myBptAmount), "Transfer of output tokens failed");
    }

    /**
     * @dev Modifier to check token allowance
     */
    modifier checkPoolSupported(address _managedPool) {
        IManagedPool managedPool = IManagedPool(_managedPool);
        require(pools[_managedPool] != address(0x0), "Error");
        _;
    }
}
