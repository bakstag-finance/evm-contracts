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

        // quote should revert
        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            mockOfferId,
            SRC_ACCEPT_AMOUNT_SD,
            addressToBytes32(srcBuyerAddress)
        );

        vm.expectRevert(abi.encodeWithSelector(IOtcMarketAcceptOffer.NonexistentOffer.selector, mockOfferId));
        aOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);
    }

    function test_RevertOn_InvalidEid() public {
        vm.deal(dstBuyerAddress, 10 ether);

        // create offer a -> b
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(SRC_AMOUNT_LD, EXCHANGE_RATE_SD);

        // try to accept on a - quote should revert
        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            receipt.offerId,
            SRC_ACCEPT_AMOUNT_SD,
            addressToBytes32(srcBuyerAddress)
        );

        vm.expectRevert(abi.encodeWithSelector(IOtcMarketAcceptOffer.InvalidEid.selector, aEid, bEid));
        aOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);
    }

    function test_RevertOn_ExcessiveAmount() public {
        vm.deal(dstBuyerAddress, 10 ether);

        // create offer a -> b
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(SRC_AMOUNT_LD, EXCHANGE_RATE_SD);

        // deliver OfferCreated message to bOtcMarket
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));

        // try to accept with the excessive amount on b - quote should revert
        uint64 excessiveAmount = SRC_AMOUNT_SD + 1;

        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            receipt.offerId,
            excessiveAmount,
            addressToBytes32(srcBuyerAddress)
        );

        vm.expectRevert(
            abi.encodeWithSelector(IOtcMarketAcceptOffer.ExcessiveAmount.selector, SRC_AMOUNT_SD, excessiveAmount)
        );
        bOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);
    }

    function test_RevertOn_InvalidDecimals() public {
        vm.deal(dstBuyerAddress, 10 ether);
        vm.deal(srcSellerAddress, 10 ether);

        // approve aOtcMarket to spend seller src tokens
        aToken.mint(srcSellerAddress, SRC_AMOUNT_LD);
        vm.prank(srcSellerAddress);
        aToken.approve(address(aOtcMarket), SRC_AMOUNT_LD);

        // approve bOtcMarket to spend buyer dst tokens
        aToken.mint(srcSellerAddress, SRC_AMOUNT_LD);
        vm.prank(srcSellerAddress);
        aToken.approve(address(aOtcMarket), SRC_AMOUNT_LD);

        // set enforced options for a
        {
            EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
            enforcedOptionsArray[0] = EnforcedOptionParam(
                bEid,
                uint16(IOtcMarketCore.Message.OfferCreated),
                OptionsBuilder
                    .newOptions()
                    .addExecutorLzReceiveOption(GAS_CREATE_OFFER, 0)
                    .addExecutorOrderedExecutionOption()
            );
            aOtcMarket.setEnforcedOptions(enforcedOptionsArray);
        }

        // set enforced options for b
        {
            EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
            enforcedOptionsArray[0] = EnforcedOptionParam(
                aEid,
                uint16(IOtcMarketCore.Message.OfferAccepted),
                OptionsBuilder
                    .newOptions()
                    .addExecutorLzReceiveOption(GAS_ACCEPT_OFFER, 0)
                    .addExecutorOrderedExecutionOption()
            );
            bOtcMarket.setEnforcedOptions(enforcedOptionsArray);
        }

        // create offer a -> b
        IOtcMarketCreateOffer.CreateOfferParams memory createOfferParams = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(xToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(
            addressToBytes32(srcSellerAddress),
            createOfferParams,
            false
        );

        vm.prank(srcSellerAddress);
        (, IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt) = aOtcMarket.createOffer{
            value: fee.nativeFee
        }(createOfferParams, fee);

        // deliver OfferCreated message to bOtcMarket
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));

        // try to accept on bOtcMarket - quote should revert
        IOtcMarketAcceptOffer.AcceptOfferParams memory acceptOfferParams = IOtcMarketAcceptOffer.AcceptOfferParams(
            createOfferReceipt.offerId,
            SRC_ACCEPT_AMOUNT_SD,
            addressToBytes32(srcBuyerAddress)
        );

        vm.expectRevert();
        bOtcMarket.quoteAcceptOffer(addressToBytes32(dstBuyerAddress), acceptOfferParams, false);
    }

    function testFuzz_UpdateBalances(
        uint256 srcAmountLD,
        uint64 exchangeRateSD,
        uint256 srcAcceptAmountLD
    ) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));
        srcAcceptAmountLD = bound(srcAcceptAmountLD, 1, srcAmountLD);

        uint64 srcAcceptAmountSD = srcAcceptAmountLD.toSD(srcDecimalConversionRate);
        vm.assume(
            (uint256(srcAcceptAmountSD) * uint256(exchangeRateSD) * srcDecimalConversionRate) >=
                uint256(10 ** aOtcMarket.SHARED_DECIMALS())
        );


        // creating offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt = _create_offer(srcAmountLD, exchangeRateSD);
        vm.recordLogs();
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));

        uint256 srcSellerBalance = ERC20(address(aToken)).balanceOf(address(srcSellerAddress));
        uint256 dstSellerBalance = ERC20(address(bToken)).balanceOf(address(dstSellerAddress));
        uint256 escrowBalance = ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow()));
        uint256 srcBuyerBalance = ERC20(address(aToken)).balanceOf(address(srcBuyerAddress));
        uint256 dstTreasuryBalance = ERC20(address(bToken)).balanceOf(address(bTreasury));

        //accepting offer

        IOtcMarketAcceptOffer.AcceptOfferReceipt memory acceptOfferReceipt = _accept_offer(
            createOfferReceipt.offerId,
            srcAcceptAmountSD
        );

        vm.recordLogs();
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));

        assertEq(ERC20(address(aToken)).balanceOf(address(srcSellerAddress)), srcSellerBalance, "src Seller balance");

        assertEq(
            ERC20(address(aToken)).balanceOf(address(srcBuyerAddress)) - srcBuyerBalance,
            srcAcceptAmountLD.removeDust(srcDecimalConversionRate),
            "src Buyer balance"
        );

        assertEq(
            escrowBalance - ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow())),
            srcAcceptAmountLD.removeDust(srcDecimalConversionRate),
            "src escrow balance"
        );

        uint256 dstAmountLD = (uint256(srcAcceptAmountSD) * uint256(exchangeRateSD) * srcDecimalConversionRate) /
            (10 ** aOtcMarket.SHARED_DECIMALS());

        assertEq(acceptOfferReceipt.dstAmountLD, dstAmountLD, "dst Amount");

        assertEq(acceptOfferReceipt.dstAmountLD / 100, acceptOfferReceipt.feeLD, "platform fee");

        assertEq(
            ERC20(address(bToken)).balanceOf(address(dstSellerAddress)) - dstSellerBalance,
            acceptOfferReceipt.dstAmountLD - acceptOfferReceipt.feeLD,
            "dst Seller balance"
        );

        assertEq(
            ERC20(address(bToken)).balanceOf(address(bTreasury)) - dstTreasuryBalance,
            acceptOfferReceipt.feeLD,
            "dst treasury balance"
        );

    }
}
