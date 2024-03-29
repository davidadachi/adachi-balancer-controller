// SPDX-License-Identifier: UNLICENSED
// !! THIS FILE WAS AUTOGENERATED BY abi-to-sol v0.6.6. SEE SOURCE BELOW. !!
pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

interface WeightedPoolNoAMFactory {
  function create ( string memory name, string memory symbol, address[] memory tokens, uint256[] memory weights, uint256 swapFeePercentage, address owner ) external returns ( address );
  function getCreationCode (  ) external view returns ( bytes memory );
  function getCreationCodeContracts (  ) external view returns ( address contractA, address contractB );
  function getPauseConfiguration (  ) external view returns ( uint256 pauseWindowDuration, uint256 bufferPeriodDuration );
  function getVault (  ) external view returns ( address );
  function isPoolFromFactory ( address pool ) external view returns ( bool );
}
