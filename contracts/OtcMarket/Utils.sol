// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
  * @dev Converts an address to bytes32.
  * @param _addr The address to convert.
  * @return The bytes32 representation of the address.
  */
function addressToBytes32(address _addr) pure returns (bytes32) {
    return bytes32(uint256(uint160(_addr)));
}

/**
  * @dev Converts bytes32 to an address.
  * @param _b The bytes32 value to convert.
  * @return The address representation of bytes32.
  */
function bytes32ToAddress(bytes32 _b) pure returns (address) {
    return address(uint160(uint256(_b)));
}

  /**
  * @dev Internal function to convert an amount from shared decimals into local decimals.
  * @param _amountSD The amount in shared decimals.
  * @return amountLD The amount in local decimals.
  */
  function toLD(uint64 _amountSD, uint256 _decimalConversionRate) pure returns (uint256 amountLD) {
      return _amountSD * _decimalConversionRate;
  }

  /**
  * @dev Internal function to convert an amount from local decimals into shared decimals.
  * @param _amountLD The amount in local decimals.
  * @return amountSD The amount in shared decimals.
  */
  function toSD(uint256 _amountLD, uint256 _decimalConversionRate) pure returns (uint64 amountSD) {
      return SafeCast.toUint64(_amountLD / _decimalConversionRate);
  }