import { expect } from 'chai';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish, Contract, ContractFactory, EventFilter, Signer } from "ethers";
import { Fragment } from 'ethers/lib/utils';

describe("HushLender", function () {

    let owner: Signer;
    let other: Signer;
    let hushlender: Contract;

    let wethERC20: Contract;
    let weth: Contract;
    let dai: Contract;

    let getWei = (eth: string) => { return ethers.utils.parseEther(eth); };
    let getEth = (wei: BigNumber) => { return wei.div("1000000000000000000") };

    beforeEach(async function () {
        [owner, other] = await ethers.getSigners();

        // We need weth
        wethERC20 = await ethers.getContractAt("IERC20", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", owner);
        weth = await ethers.getContractAt("IWETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", owner);
        dai = await ethers.getContractAt("IERC20", "0x6b175474e89094c44da98b954eedeac495271d0f", owner);

        const HushLender = await ethers.getContractFactory("HushLender", owner);
        hushlender = await HushLender.deploy();
        await hushlender.deployed();
        expect(await hushlender.owner()).to.equal(await owner.getAddress());
    });

    it("Deposit & Withdraw WETH", async function () {
        return;
        let amount = ethers.utils.parseEther("1");
        await weth.deposit({ value: amount });
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(amount);

        await wethERC20.transfer(hushlender.address, amount);
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(amount);

        await hushlender.deposit(weth.address, amount);
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
        expect(await hushlender.getAtokenBalance(weth.address)).to.equal(amount);
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);

        await hushlender.withdraw(weth.address);
        expect(await hushlender.getAtokenBalance(weth.address)).to.equal(0);
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.above(amount);
    });

    it("Deposit WETH & Borrow DAI", async function () {
        // Reset weth account        
        let curBal = await wethERC20.balanceOf(await owner.getAddress());
        await wethERC20.transfer(await other.getAddress(), curBal);
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);

        await weth.deposit({ value: getWei("1") });
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(getWei("1"));

        await wethERC20.transfer(hushlender.address, getWei("1"));
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(getWei("1"));

        // Deposit WETH
        await hushlender.deposit(weth.address, getWei("1"));
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);
        expect(await hushlender.getAtokenBalance(weth.address)).to.equal(getWei("1"));

        // Borrow 100 DAI
        await hushlender.borrow(dai.address, getWei("100"));
        expect(await dai.balanceOf(hushlender.address)).to.equal(getWei("100"));
        expect(await hushlender.getAtokenBalance(weth.address)).to.above(getWei("1"));
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);

        let daiDebt = await hushlender.getBalancesAndDebt(dai.address);
        expect(daiDebt["stableDebt"]).to.equal(getWei("100"));

        // Repay 100 dai
        await hushlender.repay(dai.address, getWei("100"));
        expect(await dai.balanceOf(hushlender.address)).to.equal(0);
        let daiDebt2 = await hushlender.getBalancesAndDebt(dai.address);
        expect(daiDebt2["stableDebt"]).to.above(0);
    });

    it("Flashloan", async function () {
        return;
        // Reset WETH balance
        let curBal = await wethERC20.balanceOf(await owner.getAddress());
        await wethERC20.transfer(await other.getAddress(), curBal);
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);

        // Fund hushlender with 1 weth
        await weth.deposit({ value: getWei("1") });
        expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(getWei("1"));
        await wethERC20.transfer(hushlender.address, getWei("1"));
        expect(await wethERC20.balanceOf(hushlender.address)).to.equal(getWei("1"));

        // Time to make the flashloan stuff

        let asset = dai.address;
        let borrowamount = getWei("2000"); // 2000 dai
        // https://api.1inch.exchange/v2.0/swap?fromTokenAddress=0x6b175474e89094c44da98b954eedeac495271d0f&toTokenAddress=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=200000000000000000000&fromAddress=0x52bc44d5378309ee2abf1539bf71de1b7d7be3b5&slippage=1
        let inchdata = "";

        await hushlender.takeFlashloan(asset, borrowamount, inchdata);

        // Now we need to look at the lend etc
        let daiDebt = await hushlender.getBalancesAndDebt(dai.address);
        console.log(daiDebt);
        console.log("aWeth balance: ", (await hushlender.getAtokenBalance(weth.address)).toString());
        console.log("weth balance: ", (await wethERC20.balanceOf(hushlender.address)).toString());
    });


});