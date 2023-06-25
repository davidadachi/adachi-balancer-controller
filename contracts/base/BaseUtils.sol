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
     * @param _manager - New manager.
     */
    function transferManagement(address _manager) public restricted {
        manager = _manager;
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
     * @param _amount - Amount that is to be transferred
     * @param _tokenAddress - Collateral token to check
     */
    modifier checkAllowance(uint _amount,
                            address _tokenAddress) {
        IERC20 token = IERC20(_tokenAddress);
        require(token.allowance(msg.sender, address(this)) >= _amount, "Error");
        _;
    }
}