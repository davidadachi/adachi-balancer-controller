// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./base/BaseController.sol";

contract ReserveRatioController is BaseController {

    // Minimum reserve ratio
    uint defaultMinRatio;
    
     /**
     * @notice Constructor for the controller implementation class
     *
     * @param _vaultAddress - Vault contract address
     * @param _managedPoolFactory - Managed pool contract address
     */
    constructor(uint _defaultMinRatio, address _vaultAddress, address _managedPoolFactory) BaseController(_vaultAddress, _managedPoolFactory)
    {
        defaultMinRatio = _defaultMinRatio;
    }

    // Managed Pools
    mapping(address => uint) public reserveRatio; // MP Address and its Reserve Ratio

    /**
     * @notice Runs a check and transfers reserve tokens as needed
     * @dev To avoid too many fees, this should be run at wide intervals such as daily
     *
     * @param _poolAddress - Address of pool being worked on.
     */
    function runCheck(address _poolAddress) public restricted
    {
        IManagedPool managedPool;
        managedPool = IManagedPool(_poolAddress);
    }

    /**
     * @notice Sets a reserve ratio
     *
     * @param _poolAddress - Address of pool being worked on.
     * @param _ratio - Reserve ratio to set
     */
    function setReserveRatio(address _poolAddress, uint _ratio) public restricted {
        reserveRatio[_poolAddress] = _ratio;
    }

    /**
     * @notice Gets a reserve ratio
     *
     * @param _poolAddress - Address of pool being worked on.
     */
    function getManagedPoolRatio(address _poolAddress) public view returns (uint) {
        return reserveRatio[_poolAddress];
    }
}
