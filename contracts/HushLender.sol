//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "hardhat/console.sol";
import {IERC20, ILendingPool, IProtocolDataProvider} from "./Interfaces.sol";
import {SafeERC20} from "./Libraries.sol";

interface IHushLender {
    function deposit(address _asset, uint256 _amount) external;

    function withdraw(address _asset) external;

    function borrow(address _asset, uint256 _amount) external;

    function repay(address _asset, uint256 _amount) external;

    function transferAsset(
        address _asset,
        uint256 _amount,
        address _to
    ) external;

    function transferAToken(
        address _asset,
        uint256 _amount,
        address _to
    ) external;

    function getAtokenBalance(address _asset) external view returns (uint256);

    function getBalancesAndDebt(address _asset)
        external
        view
        returns (
            uint256 balance,
            uint256 stableDebt,
            uint256 variableDebt
        );
}

contract HushLender is IHushLender {
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

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @notice Deposits an `amount` of `_asset` into the underlying Aave reserve and thereby receiving the overlying interestbearing aToken,
     * e.g., user deposits 1 WETH and receives 1 aWETH.
     * @param _asset The address of the underlying asset
     * @param _amount The amount to be deposited
     */
    function deposit(address _asset, uint256 _amount)
        public
        override
        onlyOwner
    {
        IERC20(_asset).safeApprove(address(lendingPool), _amount);
        lendingPool.deposit(_asset, _amount, address(this), 0);
    }

    /**
     * @notice Withdraw as much underlying `_asset` as possible by burning aTokens
     * @param _asset The address of the underlying asset from the reserve
     */
    function withdraw(address _asset) public override onlyOwner {
        lendingPool.withdraw(_asset, uint256(-1), msg.sender);
    }

    /**
     * @notice Borrow a specific `_amount` of the underlying `_asset` if the user has sufficient collateral
     * will borrow with stable interest rate and 0 as the referral code.
     * @param _asset The address of the underlying asset to borrow
     * @param _amount The amount to be borrowed
     */
    function borrow(address _asset, uint256 _amount) public override onlyOwner {
        lendingPool.borrow(_asset, _amount, 1, 0, address(this));
    }

    /**
     * @notice Repays a borrowed `_amount` on a specific reserve, burning the equivalent debt tokens.
     * will repay with stable interest rate.
     * @param _asset The address of the borrowed underlying asset previously borrowed
     * @param _amount The amount to pay back.
     */
    function repay(address _asset, uint256 _amount) public override onlyOwner {
        IERC20(_asset).safeApprove(address(lendingPool), _amount);
        lendingPool.repay(_asset, _amount, 1, address(this));
    }

    /**
     * @notice Transfers a given `amount` of the `asset` to another account.
     * @param _asset The address of the asset
     * @param _amount The amount to transfer
     * @param _to The address to receive the asset
     */
    function transferAsset(
        address _asset,
        uint256 _amount,
        address _to
    ) public override onlyOwner {
        IERC20(_asset).safeTransfer(_to, _amount);
    }

    /**
     * @notice Transfers a given `amount` of the interest bearing `asset` to another account.
     * Used as a helper function but `transferAsset` could be used with the aTokenAddress directly.
     * @param _asset The address of the underlying asset
     * @param _amount The amount of aTokens to Transfer
     * @param _to The address to receive the asset
     */
    function transferAToken(
        address _asset,
        uint256 _amount,
        address _to
    ) public override onlyOwner {
        (address aTokenAddress, , ) =
            dataProvider.getReserveTokensAddresses(_asset);
        IERC20(aTokenAddress).safeTransfer(_to, _amount);
    }

    /**
     * @notice Gets the balance of aTokens for the underlying `_asset`
     * @param _asset The address of the underlying asset
     * @return The balance of aTokens
     */
    function getAtokenBalance(address _asset)
        public
        view
        override
        returns (uint256)
    {
        (address aTokenAddress, , ) =
            dataProvider.getReserveTokensAddresses(_asset);
        return IERC20(aTokenAddress).balanceOf(address(this));
    }

    /**
     * @notice Gets the balance of aTokens, stable debt and variable debt tokens for `_asset`
     * @param _asset The address of the underlying asset
     */
    function getBalancesAndDebt(address _asset)
        public
        view
        override
        returns (
            uint256 balance,
            uint256 stableDebt,
            uint256 variableDebt
        )
    {
        (
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress
        ) = dataProvider.getReserveTokensAddresses(_asset);

        balance = IERC20(aTokenAddress).balanceOf(address(this));
        stableDebt = IERC20(stableDebtTokenAddress).balanceOf(address(this));
        variableDebt = IERC20(variableDebtTokenAddress).balanceOf(
            address(this)
        );
    }
}
