import { expect } from "chai";
import { ethers } from "hardhat";
import {
	BigNumber,
	Contract,
	Signer,
} from "ethers";

describe("HushLender", function () {
	let owner: Signer;
	let other: Signer;
	let hushlender: Contract;

	let wethERC20: Contract;
	let weth: Contract;
	let dai: Contract;

	let getWei = (eth: string) => {
		return ethers.utils.parseEther(eth);
	};
	let getEth = (wei: BigNumber) => {
		return wei.div("1000000000000000000");
	};

	beforeEach(async function () {
		[owner, other] = await ethers.getSigners();

		// We need weth
		wethERC20 = await ethers.getContractAt(
			"IERC20",
			"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
			owner
		);
		weth = await ethers.getContractAt(
			"IWETH",
			"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
			owner
		);
		dai = await ethers.getContractAt(
			"IERC20",
			"0x6b175474e89094c44da98b954eedeac495271d0f",
			owner
		);

		const HushLender = await ethers.getContractFactory("HushLender", owner);
		hushlender = await HushLender.deploy();
		await hushlender.deployed();
		expect(await hushlender.owner()).to.equal(await owner.getAddress());
	});

	it("Deposit & Withdraw WETH", async function () {
		let amount = ethers.utils.parseEther("1");
		await weth.deposit({ value: amount });
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(
			amount
		);

		await wethERC20.transfer(hushlender.address, amount);
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(amount);

		await hushlender.deposit(weth.address, amount);
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
		expect(await hushlender.getAtokenBalance(weth.address)).to.equal(
			amount
		);
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);

		await hushlender.withdraw(weth.address);
		expect(await hushlender.getAtokenBalance(weth.address)).to.equal(0);
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.above(
			amount
		);
	});

	it("Deposit WETH & Borrow DAI", async function () {
		// Reset weth account
		let curBal = await wethERC20.balanceOf(await owner.getAddress());
		await wethERC20.transfer(await other.getAddress(), curBal);
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);

		await weth.deposit({ value: getWei("1") });
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(
			getWei("1")
		);

		await wethERC20.transfer(hushlender.address, getWei("1"));
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(
			getWei("1")
		);

		// Deposit WETH
		await hushlender.deposit(weth.address, getWei("1"));
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);
		expect(await hushlender.getAtokenBalance(weth.address)).to.equal(
			getWei("1")
		);

		// Borrow 100 DAI
		await hushlender.borrow(dai.address, getWei("100"));
		expect(await dai.balanceOf(hushlender.address)).to.equal(getWei("100"));
		expect(await hushlender.getAtokenBalance(weth.address)).to.above(
			getWei("1")
		);
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);

		let daiDebt = await hushlender.getBalancesAndDebt(dai.address);
		expect(daiDebt["stableDebt"]).to.equal(getWei("100"));

		// Repay 100 dai
		await hushlender.repay(dai.address, getWei("100"));
		expect(await dai.balanceOf(hushlender.address)).to.equal(0);
		let daiDebt2 = await hushlender.getBalancesAndDebt(dai.address);
		expect(daiDebt2["stableDebt"]).to.above(0);
	});

	it("Flashloan -> leveraged eth position", async function () {
		let uniV2router = await ethers.getContractAt(
			"IRouter02",
			"0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
			owner
		);

		// Reset WETH balance
		let curBal = await wethERC20.balanceOf(await owner.getAddress());
		await wethERC20.transfer(await other.getAddress(), curBal);
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(0);

		// Fund hushlender with 1 weth
		await weth.deposit({ value: getWei("1") });
		expect(await wethERC20.balanceOf(await owner.getAddress())).to.equal(
			getWei("1")
		);
		await wethERC20.transfer(hushlender.address, getWei("1"));
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(
			getWei("1")
		);

		// Time to make the flashloan + swap
		// We will make a swap with Uniswap as I had some issues with 1inch api as we have no funds yet.
		// Note that the `hushlender` takes an address and calldata, so you can just swap it for 1inch here, no need to change the contract.

		let asset = dai.address;
		let borrowamount = getWei("2000"); // 2000 dai
		let path = [asset, weth.address];

		let blocknumber = await ethers.provider.getBlockNumber();
		let block = await ethers.provider.getBlock(blocknumber);
		let deadline = block.timestamp + 6000;

        // Generate calldata for uniswap trade
		let populated = await uniV2router.populateTransaction.swapExactTokensForTokens(
			borrowamount,
			"0",
			path,
			hushlender.address,
			deadline
		);
		let calldata = populated.data;
		// https://api.1inch.exchange/v2.0/swap?fromTokenAddress=0x6b175474e89094c44da98b954eedeac495271d0f&toTokenAddress=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&amount=200000000000000000000&fromAddress=0x52bc44d5378309ee2abf1539bf71de1b7d7be3b5&slippage=1
        
        // Encode calldata for `hushlender`.
		let abiCoder = ethers.utils.defaultAbiCoder;
		let extendedCalldata = abiCoder.encode(
			["address", "bytes"],
			[uniV2router.address, calldata]
		);

		// Pre flashloan + leverage
		let balDebtPre = await hushlender.getBalancesAndDebt(dai.address);
		expect(balDebtPre["balance"]).to.equal(0); //aDai
		expect(balDebtPre["stableDebt"]).to.equal(0); //stable debt Dai
		expect(balDebtPre["variableDebt"]).to.equal(0); // variable debt Dai

		expect(await hushlender.getAtokenBalance(weth.address)).to.equal(0);
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(
			getWei("1")
		);
		/*
		//console.log(await hushlender.getBalancesAndDebt(dai.address));
		console.log(
			"aWeth balance: ",
			(await hushlender.getAtokenBalance(weth.address)).toString()
		);
		console.log(
			"weth balance: ",
			(await wethERC20.balanceOf(hushlender.address)).toString()
		);*/

		// Performing flashloan
		await hushlender.takeFlashloan(asset, borrowamount, extendedCalldata);

		// Post flashloan + levarage
		let balDebtPost = await hushlender.getBalancesAndDebt(dai.address);
		expect(balDebtPost["balance"]).to.equal(0); // aDai
		expect(balDebtPost["stableDebt"]).to.above(getWei("2000")); // stable debt Dai
		expect(balDebtPost["variableDebt"]).to.equal(0); // variable debt Dai

		expect(await hushlender.getAtokenBalance(weth.address)).to.above(
			getWei("2")
		);
		expect(await wethERC20.balanceOf(hushlender.address)).to.equal(0);
	});
});
