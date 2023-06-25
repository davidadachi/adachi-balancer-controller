// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "../lib/SupportLib.sol";

abstract contract BaseUtils {
    address public manager;

    /**
     * @notice Transfer the manager to a new address
     * @dev Only one manager can presently be set
     *
     * @param supportedManager - New manager.
     */
    function transferManagement(address supportedManager) public restricted {
        manager = supportedManager;
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
     *
     * @param amount - Amount that is to be transferred
     * @param tokenAddress - Collateral token to check
     */
    modifier checkAllowance(uint amount, address tokenAddress) {
        IERC20 token = IERC20(tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= amount, "Error");
        _;
    }
}
