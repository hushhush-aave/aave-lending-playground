//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "hardhat/console.sol";

import {IERC20, ILendingPool, IProtocolDataProvider} from "./Interfaces.sol";
import {SafeERC20} from "./Libraries.sol";

contract HushLender {
    using SafeERC20 for IERC20;

    address public owner;

    ILendingPool constant lendingPool =
        ILendingPool(address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9));
    IProtocolDataProvider constant dataProvider =
        IProtocolDataProvider(
            address(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)
        );

    constructor() public {
        owner = msg.sender;
    }

    function deposit(address _asset, uint256 _amount) public {
        require(msg.sender == owner, "Not owner");
        IERC20(_asset).safeApprove(address(lendingPool), _amount);
        lendingPool.deposit(_asset, _amount, address(this), 0);
    }

    function getBalance(address _asset) public view returns (uint256 balance) {
        (address aTokenAddress, , ) =
            dataProvider.getReserveTokensAddresses(_asset);
        balance = IERC20(aTokenAddress).balanceOf(address(this));
    }

    function withdraw(address _asset) public {
        require(msg.sender == owner, "Not owner");
        uint256 balance = getBalance(_asset);
        lendingPool.withdraw(_asset, balance, msg.sender);
    }
}
