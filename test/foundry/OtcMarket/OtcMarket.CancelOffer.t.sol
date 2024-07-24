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

    // TODO: test where one accepts an offer partially and then seller cancels it

    function testFuzz_EmitEvents(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));

        // create offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_cancel_offer(
            srcAmountLD,
            exchangeRateSD,
            false
        );

        // cancel offer
        vm.recordLogs();
        _cancel_offer(createOfferReceipt.offerId);

        bytes32 signature = keccak256("OfferCanceled(bytes32)");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        for (uint j = 0; j < 2; j++) {
            // first iteration for dst
            // second iteration for src
            for (uint i = 0; i < entries.length; i++) {
                if (entries[i].topics[0] == signature) {
                    Vm.Log memory offerCanceledLog = entries[i];

                    assertEq(offerCanceledLog.topics[1], createOfferReceipt.offerId);
                }
            }
        }
    }

    function test_RevertOn_NonexistentOffer() public {
        bytes32 mockOfferId = addressToBytes32(makeAddr("mockOfferId"));

        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_cancel_offer(
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD,
            false
        );
        MessagingFee memory returnFee = bOtcMarket.quoteCancelOffer(createOfferReceipt.offerId);
        bytes memory extraSendOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            0,
            uint128(returnFee.nativeFee)
        );

        vm.prank(srcSellerAddress);
        vm.expectRevert(abi.encodeWithSelector(IOtcMarketCore.NonexistentOffer.selector, mockOfferId));
        aOtcMarket.quoteCancelOfferOrder(addressToBytes32(srcSellerAddress), mockOfferId, extraSendOptions, false);
    }
}
