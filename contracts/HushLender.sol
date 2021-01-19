//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "hardhat/console.sol";
import {
    IERC20,
    ILendingPool,
    IProtocolDataProvider,
    ILendingPoolAddressesProvider,
    IFlashLoanReceiver
} from "./Interfaces.sol";
import {SafeERC20, SafeMath} from "./Libraries.sol";

interface IHushLender {
    function deposit(address _asset, uint256 _amountBorrowed) external;

    function withdraw(address _asset) external;

    function borrow(address _asset, uint256 _amountBorrowed) external;

    function repay(address _asset, uint256 _amountBorrowed) external;

    function transferAsset(
        address _asset,
        uint256 _amountBorrowed,
        address _to
    ) external;

    function transferAToken(
        address _asset,
        uint256 _amountBorrowed,
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

contract HushLender is IHushLender, IFlashLoanReceiver {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

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
     * @param _amountBorrowed The amount to be deposited
     */
    function deposit(address _asset, uint256 _amountBorrowed)
        public
        override
        onlyOwner
    {
        IERC20(_asset).safeApprove(address(lendingPool), _amountBorrowed);
        lendingPool.deposit(_asset, _amountBorrowed, address(this), 0);
    }

    /**
     * @notice Withdraw as much underlying `_asset` as possible by burning aTokens
     * @param _asset The address of the underlying asset from the reserve
     */
    function withdraw(address _asset) public override onlyOwner {
        lendingPool.withdraw(_asset, uint256(-1), msg.sender);
    }

    /**
     * @notice Borrow a specific `_amountBorrowed` of the underlying `_asset` if the user has sufficient collateral
     * will borrow with stable interest rate and 0 as the referral code.
     * @param _asset The address of the underlying asset to borrow
     * @param _amountBorrowed The amount to be borrowed
     */
    function borrow(address _asset, uint256 _amountBorrowed)
        public
        override
        onlyOwner
    {
        lendingPool.borrow(_asset, _amountBorrowed, 1, 0, address(this));
    }

    /**
     * @notice Repays a borrowed `_amountBorrowed` on a specific reserve, burning the equivalent debt tokens.
     * will repay with stable interest rate.
     * @param _asset The address of the borrowed underlying asset previously borrowed
     * @param _amountBorrowed The amount to pay back.
     */
    function repay(address _asset, uint256 _amountBorrowed)
        public
        override
        onlyOwner
    {
        IERC20(_asset).safeApprove(address(lendingPool), _amountBorrowed);
        lendingPool.repay(_asset, _amountBorrowed, 1, address(this));
    }

    /**
     * @notice Transfers a given `amount` of the `asset` to another account.
     * @param _asset The address of the asset
     * @param _amountBorrowed The amount to transfer
     * @param _to The address to receive the asset
     */
    function transferAsset(
        address _asset,
        uint256 _amountBorrowed,
        address _to
    ) public override onlyOwner {
        IERC20(_asset).safeTransfer(_to, _amountBorrowed);
    }

    /**
     * @notice Transfers a given `amount` of the interest bearing `asset` to another account.
     * Used as a helper function but `transferAsset` could be used with the aTokenAddress directly.
     * @param _asset The address of the underlying asset
     * @param _amountBorrowed The amount of aTokens to Transfer
     * @param _to The address to receive the asset
     */
    function transferAToken(
        address _asset,
        uint256 _amountBorrowed,
        address _to
    ) public override onlyOwner {
        (address aTokenAddress, , ) =
            dataProvider.getReserveTokensAddresses(_asset);
        IERC20(aTokenAddress).safeTransfer(_to, _amountBorrowed);
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

    ////////////////
    // Flashloans //
    ////////////////

    /**
    * @notice Initiates a flashloan of `_amountBorrowed` of `_asset` that is to be swapped at 1inch with `_inchdata`. 
    * @param _asset The asset we want to borrow
    * @param _amountBorrowed The amount of the asset we want to borrow
    * @param _inchdata calldata used for the swap. 
     */
    function takeFlashloan(
        address _asset,
        uint256 _amountBorrowed,
        bytes calldata _inchdata
    ) public {
        address[] memory assets = new address[](1);
        assets[0] = _asset;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amountBorrowed;

        // 0 = no debt, 1 = stable, 2 = variable
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        //bytes memory params = "";
        //uint16 referralCode = 0;

        // 1. Borrow `_amountBorrowed` of `_asset`
        lendingPool.flashLoan(
            address(this), // receiverAddress
            assets,
            amounts,
            modes,
            address(this), // onBehalfOf
            _inchdata, //params
            0 // referralcode
        );
    }

    /**
     * @notice This will be called as part of the flashloan
     * @param assets The addresses of the borrowed assets
     * @param amounts The amounts of the borrowed assets
     * @param premiums The fee that we must pay to borrow
     * @param initiator The initiator of the flashswap
     * @param params The params for our function (here 1inch calldata)
     * @return True if executed
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // I have funds here. Time to do nice stuff!
        if (false) {
            initiator;
        }

        // Superlong ETH! Here we have only 1 asset.
        uint256 owns = amounts[0].add(premiums[0]);
        _superLongEth(assets[0], amounts[0], owns, params);

        // 5. Pay back flashloan
        IERC20(assets[0]).safeApprove(address(lendingPool), owns);

        return true;
    }

    /**
     * @notice Receives `_amountBorrowed` of `_asset` which it swaps to weth.
     * Then deposits weth into Aave and borrows `_amountPayback` of `_asset` to pay back loan.
     * @param _asset The asset that it receives
     * @param _amountBorrowed The amount it receives
     * @param _amountPayback The amount to pay back
     * @param _inchdata The 1inch swap data
     */
    function _superLongEth(
        address _asset,
        uint256 _amountBorrowed,
        uint256 _amountPayback,
        bytes calldata _inchdata
    ) internal {
        address inch = address(0x111111125434b319222CdBf8C261674aDB56F3ae);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        // 2. Swap _asset to WETH
        IERC20(_asset).safeApprove(inch, _amountBorrowed);
        (bool success, ) = inch.call(_inchdata);
        require(success, "1inch call failed");

        uint256 wethBalance = weth.balanceOf(address(this));
        // 3. Deposit all weth into Aave
        deposit(address(weth), wethBalance);

        // 4. Borrow enough _asset to buy back
        borrow(_asset, _amountPayback);
    }

    function LENDING_POOL() public view override returns (ILendingPool) {
        return lendingPool;
    }

    function ADDRESSES_PROVIDER()
        public
        view
        override
        returns (ILendingPoolAddressesProvider)
    {
        return dataProvider.ADDRESSES_PROVIDER();
    }
}
