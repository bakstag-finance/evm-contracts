// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

// OZ imports
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// LZ imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// BF imports
import { OtcMarketTestHelper } from "./OtcMarketTestHelper.sol";
import { AmountCast } from "../../../contracts/protocol/libs/AmountCast.sol";

import { IOtcMarketAcceptOffer } from "../../../contracts/protocol/interfaces/IOtcMarketAcceptOffer.sol";
import { IOtcMarketCreateOffer } from "../../../contracts/protocol/interfaces/IOtcMarketCreateOffer.sol";
import { IOtcMarketCore } from "../../../contracts/protocol/interfaces/IOtcMarketCore.sol";

contract CancelOffer is OtcMarketTestHelper {
    using OptionsBuilder for bytes;

    using AmountCast for uint256;
    using AmountCast for uint64;

    uint64 public constant SRC_ACCEPT_AMOUNT_SD = 10 ** 3;
    uint64 public constant SRC_AMOUNT_SD = 10 ** 6;
    uint64 public constant SRC_AMOUNT_LD = 1 ether;
    uint64 public constant EXCHANGE_RATE_SD = 15 * 10 ** 5; // 1.5 dst/src
    uint256 public constant DST_DECIMAL_CONVERSION_RATE = 10 ** 12; // e.g. ERC20

    function test_CancelOffer() public {
        // create offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _create_offer(
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD,
            false
        );

        // cancel offer
        _cancel_offer(createOfferReceipt.offerId);
    }
}
