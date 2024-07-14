// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IOtcMarketCreateOffer } from "./IOtcMarketCreateOffer.sol";
import { IOtcMarketAcceptOffer } from "./IOtcMarketAcceptOffer.sol";

interface IOtcMarket is IOtcMarketCreateOffer, IOtcMarketAcceptOffer {}
