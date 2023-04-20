const  Migrations  = artifacts.require("InternalBondingCurveController");

// ManagedPoolFactory on Celo = 0x6ea01ea80FeB4313C3329e6e9fcA751CCb2cF323
// 
module.exports = function(deployer) {
    deployer.deploy(Migrations, '0xba12222222228d8ba445958a75a0704d566bf2c8', '0xDF9B5B00Ef9bca66e9902Bd813dB14e4343Be025');
  };