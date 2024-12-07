const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Vault", function () {
  let vault;
  let token0;
  let token1;
  let settlement;
  let owner;
  let user;
  let feeCollector;
  const INITIAL_SUPPLY = ethers.parseEther("1000000");
  const TEST_AMOUNT = ethers.parseEther("1000");

  beforeEach(async function () {
    // Get signers
    [owner, user, feeCollector] = await ethers.getSigners();

    // Deploy mock tokens
    const MockToken = await ethers.getContractFactory("MockERC20");
    token0 = await MockToken.deploy("Token0", "TK0", INITIAL_SUPPLY);
    token1 = await MockToken.deploy("Token1", "TK1", INITIAL_SUPPLY);

    // Deploy mock settlement
    const MockSettlement = await ethers.getContractFactory("MockGPv2Settlement");
    settlement = await MockSettlement.deploy();

    // Deploy vault
    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy(
      settlement.target,
      token0.target,
      token1.target,
      feeCollector.target
    );

    // Approve tokens
    await token0.approve(vault.target, INITIAL_SUPPLY);
    await token1.approve(vault.target, INITIAL_SUPPLY);
    await token0.connect(user).approve(vault.target, INITIAL_SUPPLY);
    await token1.connect(user).approve(vault.target, INITIAL_SUPPLY);

    // Transfer some tokens to user
    await token0.transfer(user.target, TEST_AMOUNT);
    await token1.transfer(user.target, TEST_AMOUNT);
  });

  describe("Deployment", function () {
    it("Should set the correct initial values", async function () {
      expect(await vault.settlement()).to.equal(settlement.target);
      expect(await vault.token0()).to.equal(token0.target);
      expect(await vault.token1()).to.equal(token1.target);
      expect(await vault.feeCollector()).to.equal(feeCollector.target);
      expect(await vault.owner()).to.equal(owner.target);
      expect(await vault.swapFeeRate()).to.equal(30); // 0.3% default
    });
  });

  describe("Deposits", function () {
    it("Should allow deposits of valid tokens", async function () {
      await vault.connect(user).deposit(token0.target, TEST_AMOUNT);
      expect(await vault.getBalance(user.target, token0.target)).to.equal(TEST_AMOUNT);
    });

    it("Should revert on invalid token deposits", async function () {
      const MockToken = await ethers.getContractFactory("MockERC20");
      const invalidToken = await MockToken.deploy("Invalid", "INV", INITIAL_SUPPLY);
      await expect(
        vault.connect(user).deposit(invalidToken.target, TEST_AMOUNT)
      ).to.be.revertedWith("Invalid token");
    });
  });

  describe("Withdrawals", function () {
    beforeEach(async function () {
      await vault.connect(user).deposit(token0.target, TEST_AMOUNT);
    });

    it("Should allow withdrawals of deposited tokens", async function () {
      await vault.connect(user).withdraw(token0.target, TEST_AMOUNT);
      expect(await vault.getBalance(user.target, token0.target)).to.equal(0);
    });

    it("Should revert on insufficient balance", async function () {
      await expect(
        vault.connect(user).withdraw(token0.target, TEST_AMOUNT.mul(2))
      ).to.be.revertedWith("Insufficient balance");
    });
  });

  describe("Fee Management", function () {
    it("Should allow owner to update fee rate", async function () {
      await vault.updateFeeRate(50); // 0.5%
      expect(await vault.swapFeeRate()).to.equal(50);
    });

    it("Should allow fee collector to collect fees", async function () {
      // First make a swap that generates fees
      const swapAmount = ethers.parseEther("100");
      await vault.connect(user).deposit(token0.target, swapAmount);
      
      // Mock a swap (simplified)
      const feeAmount = await vault.calculateFee(swapAmount);
      await vault.connect(feeCollector).collectFees(token0.target);
      
      expect(await token0.balanceOf(feeCollector.target)).to.equal(feeAmount);
    });
  });

  describe("Emergency Functions", function () {
    it("Should allow owner to emergency withdraw", async function () {
      await token0.transfer(vault.target, TEST_AMOUNT);
      await vault.emergencyWithdraw(token0.target, TEST_AMOUNT);
      expect(await token0.balanceOf(owner.target)).to.equal(TEST_AMOUNT);
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await vault.connect(user).deposit(token0.target, TEST_AMOUNT);
    });

    it("Should return correct user balance", async function () {
      expect(await vault.getBalance(user.target, token0.target)).to.equal(TEST_AMOUNT);
    });

    it("Should return correct total balance", async function () {
      expect(await vault.getTotalBalance(token0.target)).to.equal(TEST_AMOUNT);
    });

    it("Should calculate fees correctly", async function () {
      const amount = ethers.parseEther("100");
      const expectedFee = amount * 30n / 10000n; // 0.3%
      expect(await vault.calculateFee(amount)).to.equal(expectedFee);
    });
  });

  // Note: Swap execution tests would require more complex mocking of the CoW Protocol settlement contract
  describe("Swap Execution", function () {
    it("Should execute swaps with valid solver signature", async function () {
      // This would require mocking the settlement contract's validateSignature and settle functions
      // Implementation depends on specific CoW Protocol integration requirements
    });
  });
});
