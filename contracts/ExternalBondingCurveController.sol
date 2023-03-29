// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

pragma experimental ABIEncoderV2;

import "./base/BaseController.sol";

contract ExternalBondingCurveController is BaseController {

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
        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
        bytes32 poolId = managedPool.getPoolId();

        uint256[] memory normalizedWeights = managedPool.getNormalizedWeights();
        IERC20[] memory tokens;
        uint256[] memory balances;
        (tokens, balances,) = vault.getPoolTokens(poolId);
        IAsset[] memory assets = _convertERC20sToAssets(tokens);

        uint256 tokenAPrice = (balances[1] / normalizedWeights[1]) / (balances[0] / normalizedWeights[0]);

        uint256[] memory joinAmounts;
        uint256[] memory exitAmounts;

        bool bJoin = false;
        bool bExit = false;

        IAsset[] memory joinAssets;
        IAsset[] memory exitAssets;

        // If token 0 price is too low then remove an amount of token 0 else if too high then add an amount of token 0
        if (tokenAPrice < managedPools[_poolAddress].prices[address(assets[0])].price)
        {
            uint256 tokenABalancePercentToMove = 100 - (100 / managedPools[_poolAddress].prices[address(tokens[0])].price * tokenAPrice);
            uint256 tokenABalanceToMove = balances[0] / 100 * tokenABalancePercentToMove;

            exitAmounts[0] = tokenABalanceToMove;
            exitAssets[0] = assets[0];
            bExit = true;
        }
        else if (tokenAPrice > managedPools[_poolAddress].prices[address(assets[0])].price)
        {
            uint256 tokenABalancePercentToMove = 100 / managedPools[_poolAddress].prices[address(tokens[0])].price * tokenAPrice - 100;
            uint256 tokenbABalanceToMove = balances[0] / 100 * tokenABalancePercentToMove;

            joinAmounts[0] = tokenbABalanceToMove;
            joinAssets[0] = assets[0];
            bJoin = true;
        }

        // Balance subsequent tokens against the first token following same logic as for token 0
        for (uint256 i = 1; i < tokens.length; i++) {
            uint256 tokenPrice = (balances[0] / normalizedWeights[0]) / (balances[i] / normalizedWeights[i]);

            if (tokenPrice < managedPools[_poolAddress].prices[address(tokens[i])].price)
            {
                uint256 tokenBalancePercentToMove = 100 - (100 / managedPools[_poolAddress].prices[address(tokens[i])].price * tokenPrice);
                uint256 tokenBalanceToMove = balances[i] / 100 * tokenBalancePercentToMove;
                
                exitAmounts[exitAmounts.length - 1] = tokenBalanceToMove;
                exitAssets[exitAssets.length - 1] = assets[i];
                bExit = true;
            }
            else if (tokenPrice < managedPools[_poolAddress].prices[address(tokens[i])].price)
            {
                uint256 tokenBalancePercentToMove = 100 / managedPools[_poolAddress].prices[address(tokens[i])].price * tokenPrice - 100;
                uint256 tokenBalanceToMove = balances[i] / 100 * tokenBalancePercentToMove;

                joinAmounts[joinAmounts.length - 1] = tokenBalanceToMove;
                joinAssets[joinAssets.length - 1] = assets[i];
                bJoin = true;
            }
        }

        // If there's tokens to remove then call exitPool
        if (bExit)
        {
            IVault.ExitPoolRequest memory newExitRequest;
            newExitRequest.assets = assets;
            newExitRequest.userData = "";
            newExitRequest.toInternalBalance = true;
            newExitRequest.minAmountsOut = exitAmounts;

            vault.exitPool(poolId,
                           address(this),
                           payable(_poolAddress),
                           newExitRequest);
        }

        // If there's tokens to add then call joinPool
        if (bJoin)
        {
            IVault.JoinPoolRequest memory newJoinRequest;
            newJoinRequest.assets = assets;
            newJoinRequest.userData = "";
            newJoinRequest.fromInternalBalance = true;
            newJoinRequest.maxAmountsIn = joinAmounts;

            vault.joinPool(poolId,
                           address(this),
                           _poolAddress,
                           newJoinRequest);
        }
    }
}
