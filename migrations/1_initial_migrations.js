const  Migrations  = artifacts.require("InternalBondingCurveController");

// Vault
// CELO: 0xD25E02047E76b688445ab154785F2642c6fe3f73
// Gnosis: 0x24F87b37F4F249Da61D89c3FF776a55c321B2773
//
// ManagedPoolFactory
// CELO: 0x960Edb2AA0960be66c65FB52e83c99c3C0F4CeD5
// Gnosis: 0x6C6a62882142bA47a12513E99f3c7fD93C3eAbE3
module.exports = function(deployer) {
    deployer.deploy(Migrations, '0x24F87b37F4F249Da61D89c3FF776a55c321B2773', '0x6C6a62882142bA47a12513E99f3c7fD93C3eAbE3');
  };