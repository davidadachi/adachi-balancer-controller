// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./base/BaseController.sol";

contract ExternalBondingCurveController is BaseController {

    struct CurveValues {
        IManagedPool managedPool;
        bytes32 poolId;
        uint256[] normalizedWeights;
        IERC20[] tokens;
        uint256[] balances;
        IAsset[] assets;
        uint256 tokenAPrice;
        uint256 tokenPrice;
        uint256[] joinAmounts;
        uint256[] exitAmounts;
        bool bJoin;
        bool bExit;
        uint256 tokenABalanceToMove;
        uint256 tokenABalancePercentToMove;
        uint256 tokenBalanceToMove;
        uint256 tokenBalancePercentToMove;
        IVault.ExitPoolRequest newExitRequest;
        IVault.JoinPoolRequest newJoinRequest;
        IAsset[] joinAssets;
        IAsset[] exitAssets;
    }

    /**
     * @notice Constructor for the controller implementation class
     *
     * @param _vaultAddress - Vault contract address
     * @param _managedPoolFactory - Managed pool contract address
     */
    constructor(address _vaultAddress,
                address _managedPoolFactory) BaseController(_vaultAddress, _managedPoolFactory) {}

    function _convertERC20ToAsset(IERC20 _token) internal pure returns (IAsset asset) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            asset := _token
        }
    }

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
        curveInfo.normalizedWeights = curveInfo.managedPool.getNormalizedWeights();

        (curveInfo.tokens, curveInfo.balances,) = vault.getPoolTokens(curveInfo.poolId);
        curveInfo.assets = _convertERC20sToAssets(curveInfo.tokens);

        curveInfo.tokenAPrice = (curveInfo.balances[1] / curveInfo.normalizedWeights[1]) / (curveInfo.balances[0] / curveInfo.normalizedWeights[0]);

        curveInfo.bJoin = false;
        curveInfo.bExit = false;

        // If token 0 price is too low then remove an amount of token 0 else if too high then add an amount of token 0
        if (curveInfo.tokenAPrice < managedPools[_poolAddress].prices[address(curveInfo.assets[0])].price)
        {
            curveInfo.tokenABalanceToMove = curveInfo.balances[0] / 100 * (100 - (100 / managedPools[_poolAddress].prices[address(curveInfo.tokens[0])].price * curveInfo.tokenAPrice));

            curveInfo.exitAmounts[0] = curveInfo.tokenABalanceToMove;
            curveInfo.exitAssets[0] = curveInfo.assets[0];
            curveInfo.bExit = true;
        }
        else if (curveInfo.tokenAPrice > managedPools[_poolAddress].prices[address(curveInfo.assets[0])].price)
        {
            curveInfo.tokenABalancePercentToMove = 100 / managedPools[_poolAddress].prices[address(curveInfo.tokens[0])].price * curveInfo.tokenAPrice - 100;
            curveInfo.tokenABalanceToMove = curveInfo.balances[0] / 100 * curveInfo.tokenABalancePercentToMove;

            curveInfo.joinAmounts[0] = curveInfo.tokenABalanceToMove;
            curveInfo.joinAssets[0] = curveInfo.assets[0];
            curveInfo.bJoin = true;
        }

        // Balance subsequent tokens against the first token following same logic as for token 0
        for (uint256 i = 1; i < curveInfo.tokens.length; i++) {
            curveInfo.tokenPrice = (curveInfo.balances[0] / curveInfo.normalizedWeights[0]) / (curveInfo.balances[i] / curveInfo.normalizedWeights[i]);

            if (curveInfo.tokenPrice < managedPools[_poolAddress].prices[address(curveInfo.tokens[i])].price)
            {
                curveInfo.tokenBalanceToMove = curveInfo.balances[i] / 100 * (100 - (100 / managedPools[_poolAddress].prices[address(curveInfo.tokens[i])].price * curveInfo.tokenPrice));
                
                curveInfo.exitAmounts[curveInfo.exitAmounts.length - 1] = curveInfo.tokenBalanceToMove;
                curveInfo.exitAssets[curveInfo.exitAssets.length - 1] = curveInfo.assets[i];
                curveInfo.bExit = true;
            }
            else if (curveInfo.tokenPrice < managedPools[_poolAddress].prices[address(curveInfo.tokens[i])].price)
            {
                curveInfo.tokenBalancePercentToMove = 100 / managedPools[_poolAddress].prices[address(curveInfo.tokens[i])].price * curveInfo.tokenPrice - 100;
                curveInfo.tokenBalanceToMove = curveInfo.balances[i] / 100 * curveInfo.tokenBalancePercentToMove;

                curveInfo.joinAmounts[curveInfo.joinAmounts.length - 1] = curveInfo.tokenBalanceToMove;
                curveInfo.joinAssets[curveInfo.joinAssets.length - 1] = curveInfo.assets[i];
                curveInfo.bJoin = true;
            }
        }

        // If there's tokens to remove then call exitPool
        if (curveInfo.bExit)
        {
            curveInfo.newExitRequest.assets = curveInfo.assets;
            curveInfo.newExitRequest.userData = "";
            curveInfo.newExitRequest.toInternalBalance = true;
            curveInfo.newExitRequest.minAmountsOut = curveInfo.exitAmounts;

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
            curveInfo.newJoinRequest.maxAmountsIn = curveInfo.joinAmounts;

            vault.joinPool(curveInfo.poolId,
                                address(this),
                                _poolAddress,
                                curveInfo.newJoinRequest);
        }
    }
}
