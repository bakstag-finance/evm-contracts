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
import { IOtcMarketCancelOffer } from "../../../contracts/protocol/interfaces/IOtcMarketCancelOffer.sol";
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

    function test_RevertOn_InvalidEid() public {
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
        vm.expectRevert(abi.encodeWithSelector(IOtcMarketCore.InvalidEid.selector, aEid, bEid));
        bOtcMarket.quoteCancelOfferOrder(
            addressToBytes32(srcSellerAddress),
            createOfferReceipt.offerId,
            extraSendOptions,
            false
        );
    }

    function test_RevertIf_NotSeller() public {
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
        MessagingFee memory fee = aOtcMarket.quoteCancelOfferOrder(
            addressToBytes32(srcSellerAddress),
            createOfferReceipt.offerId,
            extraSendOptions,
            false
        );

        vm.deal(srcBuyerAddress, 10 ether);
        vm.prank(srcBuyerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(IOtcMarketCancelOffer.OnlySeller.selector, srcSellerAddress, srcBuyerAddress)
        );
        aOtcMarket.cancelOfferOrder{ value: fee.nativeFee }(createOfferReceipt.offerId, fee, extraSendOptions);
    }

    function test_RevertOn_InvalidOptions() public {
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _create_offer(
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD,
            false
        );

        {
            EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
            enforcedOptionsArray[0] = EnforcedOptionParam(
                aEid,
                uint16(IOtcMarketCore.Message.OfferCanceled),
                OptionsBuilder
                    .newOptions()
                    .addExecutorLzReceiveOption(GAS_CANCEL_OFFER, 0)
                    .addExecutorOrderedExecutionOption()
            );

            bOtcMarket.setEnforcedOptions(enforcedOptionsArray);
        }

        {
            // no enforced options
            MessagingFee memory returnFee = bOtcMarket.quoteCancelOffer(createOfferReceipt.offerId);
            bytes memory extraSendOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
                0,
                uint128(returnFee.nativeFee)
            );

            vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, bytes("")));
            aOtcMarket.quoteCancelOfferOrder(
                addressToBytes32(srcSellerAddress),
                createOfferReceipt.offerId,
                extraSendOptions,
                false
            );
        }

        {
            {
                // set enforced options
                MessagingFee memory returnFee = bOtcMarket.quoteCancelOffer(createOfferReceipt.offerId);

                EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
                enforcedOptionsArray[0] = EnforcedOptionParam(
                    bEid,
                    uint16(IOtcMarketCore.Message.OfferCancelOrder),
                    OptionsBuilder
                        .newOptions()
                        .addExecutorLzReceiveOption(GAS_CANCEL_OFFER_ORDER, uint128(returnFee.nativeFee))
                        .addExecutorOrderedExecutionOption()
                );

                aOtcMarket.setEnforcedOptions(enforcedOptionsArray);
            }

            // no extra options
            bytes memory extraSendOptions = bytes("");

            vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, bytes("")));
            aOtcMarket.quoteCancelOfferOrder(
                addressToBytes32(srcSellerAddress),
                createOfferReceipt.offerId,
                extraSendOptions,
                false
            );
        }
    }

    function testFuzz_UpdateBalances(uint256 srcAmountLD, uint64 exchangeRateSD, uint256 srcAcceptAmountLD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate * 2, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));
        srcAcceptAmountLD = bound(srcAcceptAmountLD, srcDecimalConversionRate, srcAmountLD / 2);
        uint64 srcAcceptAmountSD = srcAcceptAmountLD.toSD(srcDecimalConversionRate);

        _set_enforced_accept_offer();

        // create offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_cancel_offer(
            srcAmountLD,
            exchangeRateSD,
            false
        );

        // accept offer
        vm.deal(dstBuyerAddress, 10 ether);
        _accept_offer(createOfferReceipt.offerId, srcAcceptAmountSD, false);
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));

        (, , , , , , uint64 remainedSrcAmount, ) = aOtcMarket.offers(createOfferReceipt.offerId);

        uint256 srcEscrowInitialBalance = ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow()));
        uint256 srcSellerInitialBalance = ERC20(address(aToken)).balanceOf(address(srcSellerAddress));

        assertEq(remainedSrcAmount, srcEscrowInitialBalance.toSD(srcDecimalConversionRate), "initial escrow balance");

        //cancel offer

        _cancel_offer(createOfferReceipt.offerId);
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));

        // bytes32 srcSellerAddress;
        // bytes32 dstSellerAddress;
        // uint32 srcEid;
        // uint32 dstEid;
        // bytes32 srcTokenAddress;
        // bytes32 dstTokenAddress;
        // uint64 srcAmountSD;
        // uint64 exchangeRateSD;
        (, , , , , , uint64 offerSrcAmount, ) = aOtcMarket.offers(createOfferReceipt.offerId);

        assertEq(offerSrcAmount, 0, "offer existance on chain a");

        (, , , , , , offerSrcAmount, ) = bOtcMarket.offers(createOfferReceipt.offerId);
        assertEq(offerSrcAmount, 0, "offer existance on chain b");

        assertEq(ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow())), 0, "escrow balance is empty");

        assertEq(
            ERC20(address(aToken)).balanceOf(address(srcSellerAddress)) - srcSellerInitialBalance,
            srcEscrowInitialBalance,
            "funds rerturned to seller"
        );
    }

    function testFuzz_NativeUpdateBalances(
        uint256 srcAmountLD,
        uint64 exchangeRateSD,
        uint256 srcAcceptAmountLD
    ) public {
        uint256 srcDecimalConversionRate = 10 ** (18 - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate * 2, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));
        srcAcceptAmountLD = bound(srcAcceptAmountLD, srcDecimalConversionRate, srcAmountLD / 2);
        uint64 srcAcceptAmountSD = srcAcceptAmountLD.toSD(srcDecimalConversionRate);

        _set_enforced_accept_offer();

        // create offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_cancel_offer(
            srcAmountLD,
            exchangeRateSD,
            true
        );

        // accept offer
        vm.deal(dstBuyerAddress, 10 ether);
        _accept_offer(createOfferReceipt.offerId, srcAcceptAmountSD, true);
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));

        (, , , , , , uint64 remainedSrcAmount, ) = aOtcMarket.offers(createOfferReceipt.offerId);

        uint256 srcEscrowInitialBalance = address(aOtcMarket.escrow()).balance;
        uint256 srcSellerInitialBalance = address(srcSellerAddress).balance;

        assertEq(remainedSrcAmount, srcEscrowInitialBalance.toSD(srcDecimalConversionRate), "initial escrow balance");

        //cancel offer

        _cancel_offer(createOfferReceipt.offerId);
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));

        // bytes32 srcSellerAddress;
        // bytes32 dstSellerAddress;
        // uint32 srcEid;
        // uint32 dstEid;
        // bytes32 srcTokenAddress;
        // bytes32 dstTokenAddress;
        // uint64 srcAmountSD;
        // uint64 exchangeRateSD;
        (, , , , , , uint64 offerSrcAmount, ) = aOtcMarket.offers(createOfferReceipt.offerId);

        assertEq(offerSrcAmount, 0, "offer existance on chain a");

        (, , , , , , offerSrcAmount, ) = bOtcMarket.offers(createOfferReceipt.offerId);
        assertEq(offerSrcAmount, 0, "offer existance on chain b");

        assertEq(address(aOtcMarket.escrow()).balance, 0, "escrow balance is empty");

        assertApproxEqAbs(
            (address(srcSellerAddress).balance - srcSellerInitialBalance).removeDust(srcDecimalConversionRate),
            srcEscrowInitialBalance,
            srcDecimalConversionRate,
            "funds rerturned to seller"
        );
    }
}
