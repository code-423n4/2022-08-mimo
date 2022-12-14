// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "../../../core/interfaces/IAddressProvider.sol";
import "../../../proxy/interfaces/IMIMOProxyRegistry.sol";

interface IMIMOAutoAction {
  struct AutomatedVault {
    bool isAutomated;
    address toCollateral;
    uint256 allowedVariation;
    uint256 targetRatio;
    uint256 triggerRatio;
    uint256 mcrBuffer;
    uint256 fixedFee;
    uint256 varFee;
  }

  struct VaultState {
    address collateralType;
    uint256 collateralValue;
    uint256 vaultDebt;
  }

  event AutomationSet(uint256 vaultId, AutomatedVault autoVault);

  function setAutomation(uint256 vaultId, AutomatedVault calldata autoParams) external;

  function a() external view returns (IAddressProvider);

  function proxyRegistry() external view returns (IMIMOProxyRegistry);

  function getAutomatedVault(uint256 vaultId) external view returns (AutomatedVault memory);

  function getOperationTracker(uint256 vaultId) external view returns (uint256);
}
