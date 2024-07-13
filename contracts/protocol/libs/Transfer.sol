// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library Transfer {
    using SafeERC20 for IERC20;

    error NativeTransferFailed(address to, uint256 value);

    /**
     * @dev Internal function to transfer tokens (from to) or native value (supplied with a function call).
     * @param _tokenAddress The address of the token to transfer (set to address(0) in case of native value).
     * @param _from The sender.
     * @param _to The receiver.
     * @param _value The amount to transfer.
     */
    function transferFrom(address _tokenAddress, address _from, address _to, uint256 _value) internal {
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
}
