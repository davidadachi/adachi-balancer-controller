// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./base/BaseController.sol";
import "./lib/SupportLib.sol";

contract BondingCurveController is BaseController {

    struct CurveValues {
        IManagedPool managedPool;
        bytes32 poolId;
        bool bJoin;
        bool bExit;
        IVault.ExitPoolRequest newExitRequest;
        IVault.JoinPoolRequest newJoinRequest;
        uint256[] tokenPrices;
        int256[] oraclePriceDeltas;
        uint256[] tokenBalancesToAdd;
        uint256[] tokenBalancesToRemove;
        uint256[] normalizedWeights;
        IERC20[] tokens;
        uint256[] balances;
        IAsset[] assets;
    }

    /**
     * @notice Constructor for the controller implementation class
     *
     * @param _vaultAddress - Vault contract address
     * @param _managedPoolFactory - Managed pool contract address
     */
    constructor(address _vaultAddress,
                address _managedPoolFactory) BaseController(_vaultAddress, _managedPoolFactory) {}

    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param _poolAddress - Address of pool being worked on.
     */
    function runCheck(address _poolAddress) public restricted nonReentrant
    {
        CurveValues memory curveInfo;
        curveInfo.managedPool = IManagedPool(_poolAddress);
        curveInfo.poolId = curveInfo.managedPool.getPoolId();
        vault.getPool(curveInfo.poolId);
        curveInfo.normalizedWeights = curveInfo.managedPool.getNormalizedWeights();

        (curveInfo.tokens, curveInfo.balances,) = vault.getPoolTokens(curveInfo.poolId);
        curveInfo.assets = SupportLib._convertERC20sToAssets(curveInfo.tokens);

        curveInfo.bJoin = false;
        curveInfo.bExit = false;
        if (curveInfo.balances[0]  > 0)
        {
            curveInfo.tokenPrices[0] = (curveInfo.balances[1] / curveInfo.normalizedWeights[1]) / (curveInfo.balances[0] / curveInfo.normalizedWeights[0]);
        }

        // Get price of other tokens
        for (uint256 i = 1; i < curveInfo.tokens.length; i++) {
            if (curveInfo.balances[i] > 0)
            {
                curveInfo.tokenPrices[i] = (curveInfo.balances[0] / curveInfo.normalizedWeights[0]) / (curveInfo.balances[i] / curveInfo.normalizedWeights[i]);
            }
        }

        // We now have a list of tokens and prices in this pool so we next get token prices from an external oracle and record the delta.
        // We don't presently have an oracle so for testing we'll use the tolerance value set when creating the pool
        for (uint256 i = 1; i < curveInfo.tokens.length; i++) {
            if (curveInfo.tokenPrices[i] > 0)
            {
                curveInfo.oraclePriceDeltas[i] = int256(managedPools[_poolAddress].tolerance);
            }
        }

        for (uint256 i = 1; i < curveInfo.tokens.length; i++) {
            if (curveInfo.oraclePriceDeltas[i] >= int256(managedPools[_poolAddress].tolerance))
            {
                curveInfo.tokenBalancesToRemove[i] = curveInfo.balances[i] / 100 * managedPools[_poolAddress].tolerance;
                curveInfo.bExit = true;
            }
            else if (curveInfo.oraclePriceDeltas[i] <= -int256(managedPools[_poolAddress].tolerance))
            {
                curveInfo.tokenBalancesToAdd[i] = curveInfo.balances[i] / 100 * managedPools[_poolAddress].tolerance;
                curveInfo.bJoin = true;
            }
            else
            {
                curveInfo.tokenBalancesToAdd[i] = 0;
                curveInfo.tokenBalancesToRemove[i] = 0;
            }
        }

        // If there's tokens to remove then call exitPool
        if (curveInfo.bExit)
        {
            curveInfo.newExitRequest.assets = curveInfo.assets;
            curveInfo.newExitRequest.userData = "";
            curveInfo.newExitRequest.toInternalBalance = true;
            curveInfo.newExitRequest.minAmountsOut = curveInfo.tokenBalancesToRemove;

            vault.exitPool(curveInfo.poolId,
                               address(this),
                               payable(_poolAddress),
                               curveInfo.newExitRequest);
        }

        // If there's tokens to add then call joinPool
        if (curveInfo.bJoin)
        {
            curveInfo.newJoinRequest.assets = curveInfo.assets;
            curveInfo.newJoinRequest.userData = "";
            curveInfo.newJoinRequest.fromInternalBalance = true;
            curveInfo.newJoinRequest.maxAmountsIn = curveInfo.tokenBalancesToAdd;

            vault.joinPool(curveInfo.poolId,
                           address(this),
                           payable(_poolAddress),
                           curveInfo.newJoinRequest);
        }
    }
}
