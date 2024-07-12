// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { OtcMarketCreateOffer } from "./modules/OtcMarketCreateOffer.sol";
import { OtcMarketCore } from "./modules/OtcMarketCore.sol";

abstract contract OtcMarket is OtcMarketCreateOffer {
    constructor(address _endpoint, address _delegate) OtcMarketCore(_endpoint, _delegate) {}
}
