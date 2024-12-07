// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("VaultModule", (m) => {
  // Get deployment parameters with placeholder defaults
  const settlement = m.getParameter("settlement", "0x9008D19f58AAbD9eD0D60971565AA8510560ab41"); // CoW Protocol Settlement
  const token0 = m.getParameter("token0", "0x0000000000000000000000000000000000000000");
  const token1 = m.getParameter("token1", "0x0000000000000000000000000000000000000000");
  const feeCollector = m.getParameter("feeCollector", "0x0000000000000000000000000000000000000000");

  // Deploy Vault contract
  const vault = m.contract("Vault", [
    settlement,
    token0,
    token1,
    feeCollector
  ]);

  return { vault };
});
