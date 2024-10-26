// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library Transfer {
    using SafeERC20 for IERC20;

    error NativeTransferFailed(address recipient, uint256 amount);
    error InvalidRecipient(address recipient);

    /**
     * @dev Transfers fungible or native tokens from a specified sender to a recipient.
     * @param token The token address (use address(0) for native currency).
     * @param from The address sending the funds.
     * @param to The address receiving the funds.
     * @param amount The amount to transfer.
     */
    function transferFrom(address token, address from, address to, uint256 amount) internal {
        if (to == address(0)) revert InvalidRecipient(to);

        if (token == address(0)) {
            // native token transfer
            (bool success, ) = to.call{ value: amount }("");
            if (!success) revert NativeTransferFailed(to, amount);
        } else {
            // fungible token transferFrom
            IERC20(token).safeTransferFrom(from, to, amount);
        }
    }
}
