const  Migrations  = artifacts.require("InternalBondingCurveController");

// ManagedPoolFactory on Celo = 0x6ea01ea80FeB4313C3329e6e9fcA751CCb2cF323
// 
module.exports = function(deployer) {
    deployer.deploy(Migrations, '0xA18808989E7EB0FcF0932fd00D007F3C118B78E7', '0x6ea01ea80FeB4313C3329e6e9fcA751CCb2cF323');
  };