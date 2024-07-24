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

contract AcceptOffer is OtcMarketTestHelper {
    using OptionsBuilder for bytes;

    using AmountCast for uint256;
    using AmountCast for uint64;

    uint64 public constant SRC_ACCEPT_AMOUNT_SD = 10 ** 3;
    uint64 public constant SRC_AMOUNT_SD = 10 ** 6;
    uint64 public constant SRC_AMOUNT_LD = 1 ether;
    uint64 public constant EXCHANGE_RATE_SD = 15 * 10 ** 5; // 1.5 dst/src
    uint256 public constant DST_DECIMAL_CONVERSION_RATE = 10 ** 12; // e.g. ERC20

    function test_RevertOn_NonexistentOffer() public {
        vm.deal(dstBuyerAddress, 10 ether);

        bytes32 mockOfferId = addressToBytes32(makeAddr("mockOfferId"));
        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            mockOfferId,
            SRC_ACCEPT_AMOUNT_SD,
            addressToBytes32(srcBuyerAddress)
        );

        // quote should revert with NonexistentOffer
        vm.expectRevert(abi.encodeWithSelector(IOtcMarketCore.NonexistentOffer.selector, mockOfferId));
        aOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);
    }

    function test_RevertOn_InvalidEid() public {
        vm.deal(dstBuyerAddress, 10 ether);

        // create offer a -> b
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(SRC_AMOUNT_LD, EXCHANGE_RATE_SD, false);

        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            receipt.offerId,
            SRC_ACCEPT_AMOUNT_SD,
            addressToBytes32(srcBuyerAddress)
        );

        // try to accept on a - quote should revert with InvalidEid
        vm.expectRevert(abi.encodeWithSelector(IOtcMarketCore.InvalidEid.selector, aEid, bEid));
        aOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);
    }

    function test_RevertOn_ExcessiveAmount() public {
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_accept_offer(
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD,
            false
        );

        uint64 excessiveAmount = SRC_AMOUNT_SD + 1;
        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            createOfferReceipt.offerId,
            excessiveAmount,
            addressToBytes32(srcBuyerAddress)
        );

        // try to accept with the excessive amount on b - quote should revert
        vm.expectRevert(
            abi.encodeWithSelector(IOtcMarketAcceptOffer.ExcessiveAmount.selector, SRC_AMOUNT_SD, excessiveAmount)
        );
        bOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);
    }

    function testFuzz_UpdateBalances(uint256 srcAmountLD, uint64 exchangeRateSD, uint256 srcAcceptAmountLD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));
        srcAcceptAmountLD = bound(srcAcceptAmountLD, srcDecimalConversionRate, srcAmountLD);
        uint64 srcAcceptAmountSD = srcAcceptAmountLD.toSD(srcDecimalConversionRate);

        // create offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_accept_offer(
            srcAmountLD,
            exchangeRateSD,
            false
        );

        uint256 dstSellerInitialBalance = ERC20(address(bToken)).balanceOf(address(dstSellerAddress));
        uint256 dstTreasuryInitialBalance = ERC20(address(bToken)).balanceOf(address(bTreasury));

        uint256 srcEscrowInitialBalance = ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow()));
        uint256 srcBuyerInitialBalance = ERC20(address(aToken)).balanceOf(address(srcBuyerAddress));

        // accept offer
        IOtcMarketAcceptOffer.AcceptOfferReceipt memory acceptOfferReceipt = _accept_offer(
            createOfferReceipt.offerId,
            srcAcceptAmountSD,
            false
        );
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));

        assertEq(
            ERC20(address(aToken)).balanceOf(address(srcBuyerAddress)),
            srcBuyerInitialBalance + srcAcceptAmountLD.removeDust(srcDecimalConversionRate),
            "src buyer balance"
        );

        assertEq(
            ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow())),
            srcEscrowInitialBalance - srcAcceptAmountLD.removeDust(srcDecimalConversionRate),
            "src escrow balance"
        );

        uint256 dstAmountLD = (uint256(srcAcceptAmountSD) * uint256(exchangeRateSD) * srcDecimalConversionRate) /
            (10 ** aOtcMarket.SHARED_DECIMALS());
        assertEq(acceptOfferReceipt.dstAmountLD, dstAmountLD, "dst amount");

        assertEq(acceptOfferReceipt.dstAmountLD / 100, acceptOfferReceipt.feeLD, "BF dst fee");

        assertEq(
            ERC20(address(bToken)).balanceOf(address(dstSellerAddress)),
            dstSellerInitialBalance + (acceptOfferReceipt.dstAmountLD - acceptOfferReceipt.feeLD),
            "dst seller balance"
        );

        assertEq(
            ERC20(address(bToken)).balanceOf(address(bTreasury)),
            dstTreasuryInitialBalance + acceptOfferReceipt.feeLD,
            "dst treasury balance"
        );
    }

    function testFuzz_EmitEvents(uint256 srcAmountLD, uint64 exchangeRateSD, uint256 srcAcceptAmountLD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));
        srcAcceptAmountLD = bound(srcAcceptAmountLD, srcDecimalConversionRate, srcAmountLD);
        uint64 srcAcceptAmountSD = srcAcceptAmountLD.toSD(srcDecimalConversionRate);

        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_accept_offer(
            srcAmountLD,
            exchangeRateSD,
            false
        );

        // accept offer
        vm.recordLogs();
        _accept_offer(createOfferReceipt.offerId, srcAcceptAmountSD, false);
        {
            bytes32 signature = keccak256("OfferAccepted(bytes32,uint64,bytes32,bytes32)");

            Vm.Log[] memory entries = vm.getRecordedLogs();

            // dst
            for (uint i = 0; i < entries.length; i++) {
                if (entries[i].topics[0] == signature) {
                    Vm.Log memory offerAcceptedLog = entries[i];

                    assertEq(offerAcceptedLog.topics[1], createOfferReceipt.offerId);
                    assertEq(offerAcceptedLog.topics[2], addressToBytes32(srcBuyerAddress));
                    assertEq(offerAcceptedLog.topics[3], addressToBytes32(dstBuyerAddress));

                    uint64 srcAmountLog = abi.decode(offerAcceptedLog.data, (uint64));

                    assertEq(srcAmountLog, srcAcceptAmountSD);
                }
            }

            // src
            for (uint i = 0; i < entries.length; i++) {
                if (entries[i].topics[0] == signature) {
                    Vm.Log memory offerAcceptedLog = entries[i];

                    assertEq(offerAcceptedLog.topics[1], createOfferReceipt.offerId);
                    assertEq(offerAcceptedLog.topics[2], addressToBytes32(srcBuyerAddress));
                    assertEq(offerAcceptedLog.topics[3], addressToBytes32(dstBuyerAddress));

                    uint64 srcAmountLog = abi.decode(offerAcceptedLog.data, (uint64));

                    assertEq(srcAmountLog, srcAcceptAmountSD);
                }
            }
        }
    }

    function test_RevertOn_InsufficientValue() public {
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_accept_offer(
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD,
            true
        );

        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            createOfferReceipt.offerId,
            uint64(SRC_ACCEPT_AMOUNT_SD),
            addressToBytes32(srcBuyerAddress)
        );

        (MessagingFee memory fee, ) = bOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);

        // accept offer
        vm.prank(dstBuyerAddress);
        vm.expectRevert();
        bOtcMarket.acceptOffer{ value: fee.nativeFee }(params, fee);
    }

    function testFuzz_NativeUpdateBalances(
        uint256 srcAmountLD,
        uint64 exchangeRateSD,
        uint256 srcAcceptAmountLD
    ) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));
        srcAcceptAmountLD = bound(srcAcceptAmountLD, srcDecimalConversionRate, srcAmountLD);
        uint64 srcAcceptAmountSD = srcAcceptAmountLD.toSD(srcDecimalConversionRate);

        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _prepare_accept_offer(
            srcAmountLD,
            exchangeRateSD,
            true
        );

        uint256 srcBuyerInitialBalance = srcBuyerAddress.balance;
        uint256 srcEscrowInitialBalance = address(aOtcMarket.escrow()).balance;

        uint256 dstSellerInitialBalance = dstSellerAddress.balance;
        uint256 dstTreasuryInitialBalance = bTreasury.balance;

        // accept offer
        IOtcMarketAcceptOffer.AcceptOfferReceipt memory acceptOfferReceipt = _accept_offer(
            createOfferReceipt.offerId,
            srcAcceptAmountSD,
            true
        );

        assertEq(
            srcBuyerAddress.balance,
            srcBuyerInitialBalance + srcAcceptAmountLD.removeDust(srcDecimalConversionRate),
            "src buyer balance"
        );

        assertEq(
            address(aOtcMarket.escrow()).balance,
            srcEscrowInitialBalance - srcAcceptAmountLD.removeDust(srcDecimalConversionRate),
            "src escrow balance"
        );

        uint256 dstAmountLD = (uint256(srcAcceptAmountSD) * uint256(exchangeRateSD) * srcDecimalConversionRate) /
            (10 ** aOtcMarket.SHARED_DECIMALS());
        assertEq(acceptOfferReceipt.dstAmountLD, dstAmountLD, "dst amount");

        assertEq(acceptOfferReceipt.dstAmountLD / 100, acceptOfferReceipt.feeLD, "BF dst fee");

        assertEq(
            dstSellerAddress.balance,
            dstSellerInitialBalance + (acceptOfferReceipt.dstAmountLD - acceptOfferReceipt.feeLD),
            "dst seller balance"
        );

        assertEq(bTreasury.balance, dstTreasuryInitialBalance + acceptOfferReceipt.feeLD, "dst treasury balance");
    }
}
