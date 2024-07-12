// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

error NativeTransferFailed(address to, uint256 value);

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

function transferFrom(address _tokenAddress, address _from, address _to, uint256 _value) {
    if (_tokenAddress == address(0)) {
        // transfer native

        if (_to == address(0)) revert NativeTransferFailed(_to, _value);

        (bool success, ) = _to.call{ value: _value }("");
        if (!success) revert NativeTransferFailed(_to, _value);
    } else {
        // transferFrom token

        IERC20(_tokenAddress).safeTransferFrom(_from, _to, _value);
    }
}

// transfer native/token
// transferFrom token
