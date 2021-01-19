# aave-lending-playground
The Aave lending playground is part of the hush-hush project. Allowing us to fiddle around with the Aave protocol to get an idea of how to interact with the protocol, and what our ZKPs need to include to be of use for the ecosystem. 

The primary contract of interest is the `HushLender`, which is a smart-contract that we are to use together with ZKP for interacting anonymously with Aave. For now, the `HushLender` is just a smart contract that interacts with Aave but without any of the spicy moonmath. Nevertheless, the contract support some more complex interactions with Aave, such as **leveraged deposits**. 

## Leveraged Deposit
To make it easy to create a leveraged position on Aave, the `HushLender` can utilise a flashloan together with currently owned `WETH` to "superlong eth", which here is just a fun way to say leveraged. The contract needs to have some `WETH` before executing the action as it can otherwise not repay the flashloan. So what does it actually do? Assume that we have `1 WETH` at the contract and that we want to extend our leverage with 2K DAI. Then it does as follows:
1. Take a flashloan of 2000 DAI
2. Swap 2000 DAI for x WETH
3. Deposit (x+1) WETH into Aave
4. Borrow (2000 + fee) DAI from Aave
5. Pay back the flashloan + fees with the borrowed DAI
6. You now have a position on around 2.4 Ether earning interest on Aave (and approx 2K DAI in debt). 

The swap is currently performed at Uniswap hence we had issues receiving a useful response from the 1inch API as the account do not have neither approval nor balance before the flashloan occurs :/. However, as the `HushLender` swaps as seen below, we could just point it to 1inch when that is up and running and compute the matching `_params` bytes.
```solidity
    (   address _swapaddress,
        bytes memory _calldata
    ) = abi.decode(_params, (address, bytes));

    // 2. Swap _asset to WETH
    IERC20(_asset).safeApprove(_swapaddress, _amountBorrowed);
    (bool success, ) = _swapaddress.call(_calldata);
    require(success, "Swap call failed");
```
While this may not be the best solution from a security point of view, it should do for now hence only elevated users can start the flashloan - but look out for injections :eyes:

To get an idea of how the calldata is generated look at the `HushLender-test.ts`. 


## Testing
To make testing against a forked mainnet easy we provide an infura api key in the configuration `hardhat.config.ts`. Please only use this key to see that the contract work, and replace with your own afterwards. If misused, we will shut down the api-key.