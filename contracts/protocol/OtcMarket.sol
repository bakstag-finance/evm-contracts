// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OtcMarketCreateOffer } from "./OtcMarketCreateOffer.sol";
import { OtcMarketCore } from "./OtcMarketCore.sol";

abstract contract OtcMarket is OtcMarketCreateOffer {
    constructor(address _escrow, address _endpoint, address _delegate) OtcMarketCore(_escrow, _endpoint, _delegate) {}
}
