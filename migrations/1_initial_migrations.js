const  Migrations  = artifacts.require("InternalBondingCurveController");

// Vault
// CELO: 0xD25E02047E76b688445ab154785F2642c6fe3f73
// Gnosis: 0x24F87b37F4F249Da61D89c3FF776a55c321B2773
//
// ManagedPoolFactory
// CELO: 0x960Edb2AA0960be66c65FB52e83c99c3C0F4CeD5
// Gnosis: 0xCC6a719F645BAf3a72d71cda8884328CB9aC4605
// Gnosis (news): 0x684D63087465fd2fC05FB5E4A9129650dd6Ae3D0

module.exports = function(deployer) {
    deployer.deploy(Migrations, '0x24F87b37F4F249Da61D89c3FF776a55c321B2773', '0x684D63087465fd2fC05FB5E4A9129650dd6Ae3D0');
  };