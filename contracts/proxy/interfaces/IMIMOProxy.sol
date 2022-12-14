// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

/// @title IMIMOProxy
/// @notice Proxy contract to compose transactions on owner's behalf.
interface IMIMOProxy {
  /// EVENTS ///

  event Execute(address indexed target, bytes data, bytes response);

  event TransferOwnership(address indexed oldOwner, address indexed newOwner);

  /// PUBLIC CONSTANT FUNCTIONS ///

  /// @notice Initializes the MIMOProxy contract
  /// @dev This replaces the constructor function and can only be called once per contract instance 
  function initialize() external;

  /// @notice Returns a boolean flag that indicates whether the envoy has permission to call the given target contract's given selector method 
  /// @param envoy The caller 
  /// @param target The target contract called by the envoy  
  /// @param selector The selector of the method of the target contract called by the envoy
  /// contract and function selector.
  function getPermission(
    address envoy,
    address target,
    bytes4 selector
  ) external view returns (bool);

  /// @notice The address of the owner account or contract.
  function owner() external view returns (address);

  /// @notice How much gas to reserve for running the remainder of the "execute" function after the DELEGATECALL.
  /// @dev This prevents the proxy from becoming unusable if EVM opcode gas costs change in the future.
  function minGasReserve() external view returns (uint256);

  /// PUBLIC NON-CONSTANT FUNCTIONS ///

  /// @notice Delegate calls to the target contract by forwarding the call data. Returns the data it gets back,
  /// including when the contract call reverts with a reason or custom error.
  ///
  /// @dev Requirements:
  /// - The caller must be either an owner or an envoy.
  /// - `target` must be a deployed contract.
  /// - The owner cannot be changed during the DELEGATECALL.
  ///
  /// @param target The address of the target contract.
  /// @param data Function selector plus ABI encoded data.
  /// @return response The response received from the target contract.
  function execute(address target, bytes calldata data) external payable returns (bytes memory response);

  /// @notice Gives or takes a permission from an envoy to call the given target contract and function selector
  /// on behalf of the owner.
  /// @dev It is not an error to reset a permission on the same (envoy,target,selector) tuple multiple types.
  ///
  /// Requirements:
  /// - The caller must be the owner.
  ///
  /// @param envoy The address of the envoy account.
  /// @param target The address of the target contract.
  /// @param selector The 4 byte function selector on the target contract.
  /// @param permission The boolean permission to set.
  function setPermission(
    address envoy,
    address target,
    bytes4 selector,
    bool permission
  ) external;

  /// @notice Transfers the owner of the contract to a new account.
  /// @dev Requirements:
  /// - The caller must be the owner.
  /// @param newOwner The address of the new owner account.
  function transferOwnership(address newOwner) external;

  /// @notice Batches multiple proxy calls within a same transaction. 
  /// @param targets An array of contract addresses to call 
  /// @param data The bytes for each batched function call 
  function multicall(address[] calldata targets, bytes[] calldata data) external returns (bytes[] memory);
}
