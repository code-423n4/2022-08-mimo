// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "./MIMOFlashloan.sol";
import "./MIMOSwap.sol";
import "./interfaces/IMIMORebalance.sol";
import "../core/interfaces/IVaultsCore.sol";
import "../proxy/interfaces/IMIMOProxy.sol";

/**
  @title A SuperVault V2 action contract that can be used to rebalance a an existing vault's debt and collateral to another collateral
  @notice Should only be accessed through a MIMOProxy delegateCall
 */
contract MIMORebalance is MIMOFlashloan, MIMOSwap, IMIMORebalance {
  using SafeERC20 for IERC20;

  IMIMOProxyRegistry public immutable proxyRegistry;

  /**
    @param _a The addressProvider for the MIMO protocol
    @param _dexAP The dexAddressProvider for the MIMO protocol
    @param _lendingPool The AAVE lending pool used for flashloans
    @param _proxyRegistry The MIMOProxyRegistry used to verify access control
 */
  constructor(
    IAddressProvider _a,
    IDexAddressProvider _dexAP,
    IPool _lendingPool,
    IMIMOProxyRegistry _proxyRegistry
  ) MIMOFlashloan(_lendingPool) MIMOSwap(_a, _dexAP) {
    if (address(_proxyRegistry) == address(0)) {
      revert CustomErrors.CANNOT_SET_TO_ADDRESS_ZERO();
    }
    proxyRegistry = _proxyRegistry;
  }

  /**
    @notice Uses a flashloan to exchange one collateral type for another, e.g. to hold less volatile collateral
    @notice Vault must have been created though a MIMOProxy
    @dev Should be called by MIMOProxy through a delegatecall 
    @dev Uses an AAVE V3 flashLoan that will call executeOperation
    @param _calldata Bytes containing FlashloanData struct, RebalanceData struct, SwapData struct
   */
  function executeAction(bytes calldata _calldata) external override {
    (FlashLoanData memory flData, RebalanceData memory rbData, SwapData memory swapData) = abi.decode(
      _calldata,
      (FlashLoanData, RebalanceData, SwapData)
    );
    bytes memory params = abi.encode(msg.sender, rbData, swapData);

    _takeFlashLoan(flData, params);
  }

  /**
    @notice Executes a rebalance operation after taking a flashloan 
    @dev Integrates with AAVE V3 flashLoans
    @param assets Address array with one element corresponding to the address of the reblanced asset
    @param amounts Uint array with one element corresponding to the amount of the rebalanced asset
    @param premiums Uint array with one element corresponding to the flashLoan fees
    @param initiator Initiator of the flashloan; can only be MIMOProxy owner
    @param params Bytes sent by this contract containing MIMOProxy owner, RebalanceData struct and SwapData struct
   */
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    (address owner, RebalanceData memory rbData, SwapData memory swapData) = abi.decode(
      params,
      (address, RebalanceData, SwapData)
    );
    IMIMOProxy mimoProxy = IMIMOProxy(proxyRegistry.getCurrentProxy(owner));

    if (initiator != address(mimoProxy)) {
      revert CustomErrors.INITIATOR_NOT_AUTHORIZED(initiator, address(mimoProxy));
    }
    if (msg.sender != address(lendingPool)) {
      revert CustomErrors.CALLER_NOT_LENDING_POOL(msg.sender, address(lendingPool));
    }

    IERC20 fromCollateral = IERC20(assets[0]);
    uint256 amount = amounts[0];
    fromCollateral.safeTransfer(address(mimoProxy), amounts[0]);
    uint256 flashloanRepayAmount = amount + premiums[0];

    IMIMOProxy(mimoProxy).execute(
      address(this),
      abi.encodeWithSignature(
        "rebalanceOperation(address,uint256,uint256,uint256,(address,uint256,uint256),(uint256,bytes))",
        fromCollateral,
        amount,
        flashloanRepayAmount,
        0,
        rbData,
        swapData
      )
    );

    fromCollateral.safeIncreaseAllowance(address(lendingPool), flashloanRepayAmount);

    return true;
  }

  /**
    @notice Used by executeOperation through MIMOProxy callback to perform rebalance logic within MIMOProxy context
    @param fromCollateral The ERC20 token to rebalance from
    @param swapAmount The amount of collateral to swap to for par to repay vaultdebt
    @param flashloanRepayAmount The amount that needs to be repaid for the flashloan
    @param fee Optional fee to be passed in the context of a ManagedRebalance to mint additional stablex to pay manager
    @param rbData RebalanceData passed from the flashloan call
    @param swapData SwapData passed from the flashloan call
   */
  function rebalanceOperation(
    IERC20 fromCollateral,
    uint256 swapAmount,
    uint256 flashloanRepayAmount,
    uint256 fee,
    RebalanceData calldata rbData,
    SwapData calldata swapData
  ) external override {
    IVaultsCore core = a.core();
    _aggregatorSwap(fromCollateral, swapAmount, swapData);
    uint256 depositAmount = rbData.toCollateral.balanceOf(address(this));
    rbData.toCollateral.safeIncreaseAllowance(address(core), depositAmount);
    core.depositAndBorrow(address(rbData.toCollateral), depositAmount, rbData.mintAmount + fee);
    core.repay(rbData.vaultId, rbData.mintAmount);
    require(
      a.vaultsData().vaultCollateralBalance(rbData.vaultId) >= flashloanRepayAmount,
      Errors.CANNOT_REPAY_FLASHLOAN
    );
    core.withdraw(rbData.vaultId, flashloanRepayAmount);
    fromCollateral.safeTransfer(msg.sender, flashloanRepayAmount);
    if (fee > 0) {
      IERC20(a.stablex()).safeTransfer(msg.sender, fee);
    }
  }
}
