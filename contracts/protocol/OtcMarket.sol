// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OtcMarketCore } from "./OtcMarketCore.sol";
import { OtcMarketCreateOffer } from "./OtcMarketCreateOffer.sol";
import { OtcMarketAcceptOffer } from "./OtcMarketAcceptOffer.sol";

contract OtcMarket is OtcMarketCreateOffer, OtcMarketAcceptOffer {
    constructor(
        address _treasury,
        address _endpoint,
        address _delegate
    ) OtcMarketCore(_treasury, _endpoint, _delegate) Ownable(_delegate) {}
}
