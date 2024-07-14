// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OtcMarketCore } from "./OtcMarketCore.sol";
import { OtcMarketCreateOffer } from "./OtcMarketCreateOffer.sol";
import { OtcMarketAcceptOffer } from "./OtcMarketAcceptOffer.sol";

abstract contract OtcMarket is OtcMarketCreateOffer, OtcMarketAcceptOffer {
    constructor(address _escrow, address _endpoint, address _delegate) OtcMarketCore(_escrow, _endpoint, _delegate) {}
}
