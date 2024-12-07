const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("VaultFactory",  (m) => {
  const vaultFactory =  m.contract("VaultFactory", []);
  
  return { vaultFactory };
}); 