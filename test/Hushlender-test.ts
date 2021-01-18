import { expect } from 'chai';
import { ethers } from "hardhat";
import { BigNumberish, Contract, ContractFactory, EventFilter, Signer } from "ethers";
import { Fragment } from 'ethers/lib/utils';

describe("HushLender", function () {

    let owner: Signer;

    beforeEach(async function () {
        [owner] = await ethers.getSigners();
    });

    it("Deposit & Withdraw WETH", async function () {
        const HushLender = await ethers.getContractFactory("HushLender", owner);
        const hushlender = await HushLender.deploy();

        await hushlender.deployed();

        expect(await hushlender.owner()).to.equal(await owner.getAddress());

        // We need weth
        const wethERC20 = await ethers.getContractAt("IERC20", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", owner);
        const weth = await ethers.getContractAt("IWETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", owner);

        let amount = ethers.utils.parseEther("1");
        await weth.deposit({value: amount});
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(amount);

        await wethERC20.transfer(hushlender.address, amount);
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(amount);

        await hushlender.deposit(weth.address, amount);
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
        expect(await hushlender.getBalance(weth.address)).to.equal(amount);
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);
        
        await hushlender.withdraw(weth.address);
        expect(await hushlender.getBalance(weth.address)).to.equal(0);
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.above(amount);

    });

});