// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library AmountCast {
    /**
     * @dev Internal function to convert an amount from shared decimals into local decimals.
     * @param _amountSD The amount in shared decimals.
     * @param _decimalConversionRate The decimal conversion rate.
     * @return amountLD The amount in local decimals.
     */
    function toLD(uint64 _amountSD, uint256 _decimalConversionRate) internal pure returns (uint256 amountLD) {
        amountLD = _amountSD * _decimalConversionRate;
    }

    /**
     * @dev Internal function to convert an amount from local decimals into shared decimals.
     * @param _amountLD The amount in local decimals.
     * @param _decimalConversionRate The decimal conversion rate.
     * @return amountSD The amount in shared decimals.
     */
    function toSD(uint256 _amountLD, uint256 _decimalConversionRate) internal pure returns (uint64 amountSD) {
        amountSD = SafeCast.toUint64(_amountLD / _decimalConversionRate);
    }

    /**
     * @dev Internal function to remove dust from the given local decimal amount.
     * @param _amountLD The amount in local decimals.
     * @param _decimalConversionRate The decimal conversion rate.
     * @return amountLD The amount after removing dust in local decimals.
     *
     * @dev Prevents the loss of dust when moving amounts between chains with different decimals.
     * @dev eg. uint(123) with a conversion rate of 100 becomes uint(100).
     */
    function removeDust(uint256 _amountLD, uint256 _decimalConversionRate) public pure returns (uint256 amountLD) {
        amountLD = (_amountLD / _decimalConversionRate) * _decimalConversionRate;
    }
}
