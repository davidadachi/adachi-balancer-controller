 const  ReserveControllerMigration  = artifacts.require("WeightedReserveController");
 const  BondingCurveControllerMigration  = artifacts.require("WeightedBondingCurveController");

// Vault
// CELO: 0xD25E02047E76b688445ab154785F2642c6fe3f73
// Gnosis: 0x24F87b37F4F249Da61D89c3FF776a55c321B2773
//
// ManagedPoolFactory
// CELO: 0x6672dBA088B0151f29D05dd52117626fDE4a8B0C
// Gnosis: 0x6C6a62882142bA47a12513E99f3c7fD93C3eAbE3

// WeightedPoolNoAMFactory
// CELO: 0x47B7bdA16AB8B617E976c83A2c3c8664944d8Ed2
// Gnosis: 
module.exports = function(deployer) {
//    deployer.deploy(ReserveControllerMigration, '0xD25E02047E76b688445ab154785F2642c6fe3f73', '0x9bB01f19D9AC3a70e469863BA7Cb521a0B926e5a');
//    deployer.deploy(BondingCurveControllerMigration, '0xD25E02047E76b688445ab154785F2642c6fe3f73', '0x9bB01f19D9AC3a70e469863BA7Cb521a0B926e5a');
//    deployer.deploy(ReserveControllerMigration, '0xD25E02047E76b688445ab154785F2642c6fe3f73', '0x47B7bdA16AB8B617E976c83A2c3c8664944d8Ed2');
    deployer.deploy(BondingCurveControllerMigration, '0xD25E02047E76b688445ab154785F2642c6fe3f73', '0x47B7bdA16AB8B617E976c83A2c3c8664944d8Ed2');
  };