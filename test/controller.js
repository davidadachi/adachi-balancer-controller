const BondingCurveController = artifacts.require("BondingCurveController");

contract('BondingCurveController', (accounts) => {

  let bondingCurveController;

  console.log("ACCOUNTS:");
  console.log(accounts);

  beforeEach(async () => {
    bondingCurveController = await BondingCurveController.deployed();
  })

  
  it('runs a check on adding one pool', async () => {
    await bondingCurveController.createPool("TestPool1",
    "TestPool1",
    ['0x765DE816845861e75A25fCA122bb6898B8B1282a','0x7c64aD5F9804458B8c9F93f7300c15D55956Ac2a'],
    [25,75],
    [accounts[0]],
    25,
    true,
    true,
    25,
    25);
    const managedPoolSet = (await bondingCurveController.managedPools.call(accounts[0]));
    assert.equal(managedPoolSet, true);
  });
  
/*
  it('runs a check on adding one pool', async () => {
    await bondingCurveController.createPool("TestPool1",
    "TestPool1",
    ['0x765DE816845861e75A25fCA122bb6898B8B1282a','0x7c64aD5F9804458B8c9F93f7300c15D55956Ac2a'],
    [25,75],
    [accounts[0]],
    25,
    true,
    true,
    25,
    25);
    const managedPoolSet = (await bondingCurveController.managedPools.call(accounts[0]));
    assert.equal(managedPoolSet, true);
  });
*/

  it('transfers management', async () => {
    await bondingCurveController.transferManagement(accounts[1]);
    const manager = (await bondingCurveController.manager.call());
    assert.equal(accounts[1], manager);
  });
});

