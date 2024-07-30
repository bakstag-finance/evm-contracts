// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OtcMarketCore } from "./OtcMarketCore.sol";
import { OtcMarketCreateOffer } from "./OtcMarketCreateOffer.sol";
import { OtcMarketAcceptOffer } from "./OtcMarketAcceptOffer.sol";
import { OtcMarketCancelOffer } from "./OtcMarketCancelOffer.sol";

contract OtcMarket is OtcMarketCore, OtcMarketCreateOffer, OtcMarketAcceptOffer, OtcMarketCancelOffer {
    constructor(
        address _treasury,
        address _endpoint,
        address _delegate
    ) OtcMarketCore(_treasury, _endpoint, _delegate) {}
}
