// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OtcMarket } from "./OtcMarket.sol";

/**
 * @dev See {IOtcMarket}.
 */
contract MyOtcMarket is OtcMarket {
    constructor(
        address _escrow,
        address _endpoint,
        address _delegate
    ) OtcMarket(_escrow, _endpoint, _delegate) Ownable(_delegate) {}
}
