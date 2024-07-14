// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

// OZ imports
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// LZ imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { IOAppCore } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppCore.sol";

// BF imports
import { OtcMarketTestHelper } from "./OtcMarketTestHelper.sol";

// BF imports
import { AmountCast } from "../../../contracts/protocol/libs/AmountCast.sol";

// BF imports
import { IOtcMarketCore } from "../../../contracts/protocol/interfaces/IOtcMarketCore.sol";
import { IOtcMarketCreateOffer } from "../../../contracts/protocol/interfaces/IOtcMarketCreateOffer.sol";

import { MyToken } from "../../../contracts/MyToken.sol";
import { Escrow } from "../../../contracts/protocol/Escrow.sol";

contract CreateOffer is OtcMarketTestHelper {
    using OptionsBuilder for bytes;

    using AmountCast for uint256;
    using AmountCast for uint64;

    function _create_offer(
        uint256 srcAmountLD,
        uint64 exchangeRateSD
    ) private returns (IOtcMarketCreateOffer.CreateOfferReceipt memory receipt) {
        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(GAS_CREATE_OFFER, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(
            bEid,
            uint16(IOtcMarketCore.Message.OfferCreated),
            enforcedOptions
        );

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // mint src token
        aToken.mint(advertiser, srcAmountLD);

        // approve aOtcMarket to spend src token
        vm.prank(advertiser);
        aToken.approve(address(aOtcMarket), srcAmountLD);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(beneficiary),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        // create an offer
        vm.prank(advertiser);
        (, receipt) = aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
    }

    function testFuzz_EmitOfferCreated(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

        vm.assume(srcAmountLD >= srcDecimalConversionRate && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

        address advertiser = makeAddr("seller");
        address beneficiary = makeAddr("beneficiary");

        uint64 srcAmountSD = srcAmountLD.toSD(srcDecimalConversionRate);

        // should emit OfferCreated
        vm.recordLogs();
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        Vm.Log memory offerCreatedLog = entries[3];

        // verify offerId is a topic
        assertEq(offerCreatedLog.topics[1], receipt.offerId);

        // assert data
        IOtcMarketCore.Offer memory offer = abi.decode(offerCreatedLog.data, (IOtcMarketCore.Offer));

        assertEq(offer.advertiser, addressToBytes32(advertiser), "advertiser");
        assertEq(offer.beneficiary, addressToBytes32(beneficiary), "beneficiary");
        assertEq(offer.srcEid, aEid, "srcEid");
        assertEq(offer.dstEid, bEid, "dstEid");
        assertEq(offer.srcTokenAddress, addressToBytes32(address(aToken)), "srcTokenAddress");
        assertEq(offer.dstTokenAddress, addressToBytes32(address(bToken)), "dstTokenAddress");
        assertEq(offer.srcAmountSD, srcAmountSD, "srcAmountSD");
        assertEq(offer.exchangeRateSD, exchangeRateSD, "exchangeRateSD");
    }

    function testFuzz_StoreOffer(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

        vm.assume(srcAmountLD >= srcDecimalConversionRate && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

        address advertiser = makeAddr("seller");
        address beneficiary = makeAddr("beneficiary");

        uint64 srcAmountSD = srcAmountLD.toSD(srcDecimalConversionRate);

        // should store offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        (
            bytes32 aAdversiter,
            bytes32 aBeneficiary,
            uint32 aSrcEid,
            uint32 aDstEid,
            bytes32 aSrcTokenAddress,
            bytes32 aDstTokenAddress,
            uint64 aSrcAmountSD,
            uint64 aExchangeRateSD
        ) = aOtcMarket.offers(receipt.offerId);

        assertEq(aAdversiter, addressToBytes32(advertiser), "advertiser");
        assertEq(aBeneficiary, addressToBytes32(beneficiary), "beneficiary");
        assertEq(aSrcEid, aEid, "srcEid");
        assertEq(aDstEid, bEid, "dstEid");
        assertEq(aSrcTokenAddress, addressToBytes32(address(aToken)), "srcTokenAddress");
        assertEq(aDstTokenAddress, addressToBytes32(address(bToken)), "dstTokenAddress");
        assertEq(aSrcAmountSD, srcAmountSD, "srcAmountSD");
        assertEq(aExchangeRateSD, exchangeRateSD, "exchangeRateSD");
    }

    function testFuzz_UpdateBalances(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

        vm.assume(srcAmountLD >= srcDecimalConversionRate && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

        address advertiser = makeAddr("seller");

        // should update balances
        uint256 advertiserInitialBalance = srcAmountLD;
        uint256 escrowInitialBalance = ERC20(address(aToken)).balanceOf(address(aEscrow));

        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        uint256 advertiserUpdatedBalance = ERC20(address(aToken)).balanceOf(advertiser);
        uint256 escrowUpdatedBalance = ERC20(address(aToken)).balanceOf(address(aEscrow));

        assertEq(advertiserUpdatedBalance, advertiserInitialBalance - receipt.srcAmountLD, "advertiser balance");
        assertEq(escrowUpdatedBalance, escrowInitialBalance + receipt.srcAmountLD, "escrow balance");
    }

    function test_RevertOn_InvalidPricing() public {
        uint256 srcAmountLD = 1 ether;
        uint64 exchangeRateSD = 10 ** 6;

        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(GAS_CREATE_OFFER, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(
            bEid,
            uint16(IOtcMarketCore.Message.OfferCreated),
            enforcedOptions
        );

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // invalid source amount
        {
            // quote fee
            IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
                addressToBytes32(beneficiary),
                bEid,
                addressToBytes32(address(aToken)),
                addressToBytes32(address(bToken)),
                0,
                exchangeRateSD
            );

            (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

            // create an offer
            vm.prank(advertiser);
            vm.expectRevert(abi.encodeWithSelector(IOtcMarketCore.InsufficientAmount.selector, 1, 0));
            aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
        }

        // invalid exchange rate
        {
            // quote fee
            IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
                addressToBytes32(beneficiary),
                bEid,
                addressToBytes32(address(aToken)),
                addressToBytes32(address(bToken)),
                srcAmountLD,
                0
            );

            (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

            // create an offer
            vm.prank(advertiser);
            vm.expectRevert(abi.encodeWithSelector(IOtcMarketCreateOffer.InsufficientExchangeRate.selector, 1, 0));
            aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
        }
    }

    function test_RevertIf_OfferAlreadyExists() public {
        uint256 srcAmountLD = 1 ether;
        uint64 exchangeRateSD = 10 ** 6;

        // create an offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(GAS_CREATE_OFFER, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(
            bEid,
            uint16(IOtcMarketCore.Message.OfferCreated),
            enforcedOptions
        );

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(beneficiary),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        // try to create a dublicate offer
        vm.prank(advertiser);
        vm.expectRevert(abi.encodeWithSelector(IOtcMarketCreateOffer.OfferAlreadyExists.selector, receipt.offerId));
        aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
    }

    function test_ReceiveOfferCreated(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

        vm.assume(srcAmountLD >= srcDecimalConversionRate && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

        address advertiser = makeAddr("seller");
        address beneficiary = makeAddr("beneficiary");

        uint64 srcAmountSD = srcAmountLD.toSD(srcDecimalConversionRate);

        // create an offer on aOtcMarket
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        // deliver OfferCreated message to bOtcMarket
        vm.recordLogs();
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));

        // verify that OfferCreated event was emitted
        {
            Vm.Log[] memory entries = vm.getRecordedLogs();

            Vm.Log memory offerCreatedLog = entries[2];

            // verify offerId is a topic
            assertEq(offerCreatedLog.topics[1], receipt.offerId);

            // assert data
            IOtcMarketCore.Offer memory offer = abi.decode(offerCreatedLog.data, (IOtcMarketCore.Offer));

            assertEq(offer.advertiser, addressToBytes32(advertiser), "advertiser");
            assertEq(offer.beneficiary, addressToBytes32(beneficiary), "beneficiary");
            assertEq(offer.srcEid, aEid, "srcEid");
            assertEq(offer.dstEid, bEid, "dstEid");
            assertEq(offer.srcTokenAddress, addressToBytes32(address(aToken)), "srcTokenAddress");
            assertEq(offer.dstTokenAddress, addressToBytes32(address(bToken)), "dstTokenAddress");
            assertEq(offer.srcAmountSD, srcAmountSD, "srcAmountSD");
            assertEq(offer.exchangeRateSD, exchangeRateSD, "exchangeRateSD");
        }

        // verify that offer was stored on bOtcMarket
        {
            (
                bytes32 bAdversiter,
                bytes32 bBeneficiary,
                uint32 bSrcEid,
                uint32 bDstEid,
                bytes32 bSrcTokenAddress,
                bytes32 bDstTokenAddress,
                uint64 bSrcAmountSD,
                uint64 bExchangeRateSD
            ) = bOtcMarket.offers(receipt.offerId);

            assertEq(bAdversiter, addressToBytes32(advertiser), "advertiser");
            assertEq(bBeneficiary, addressToBytes32(beneficiary), "beneficiary");
            assertEq(bSrcEid, aEid, "srcEid");
            assertEq(bDstEid, bEid, "dstEid");
            assertEq(bSrcTokenAddress, addressToBytes32(address(aToken)), "srcTokenAddress");
            assertEq(bDstTokenAddress, addressToBytes32(address(bToken)), "dstTokenAddress");
            assertEq(bSrcAmountSD, srcAmountSD, "srcAmountSD");
            assertEq(bExchangeRateSD, exchangeRateSD, "exchangeRateSD");
        }
    }

    function test_RevertOn_InsufficientValue() public {
        uint256 srcAmountLD = 1 ether;
        uint64 exchangeRateSD = 10 ** 6;

        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(GAS_CREATE_OFFER, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(
            bEid,
            uint16(IOtcMarketCore.Message.OfferCreated),
            enforcedOptions
        );

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(beneficiary),
            bEid,
            addressToBytes32(address(0)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        // enough only for srcAmountLD
        vm.prank(advertiser);
        vm.expectRevert();
        aOtcMarket.createOffer{ value: srcAmountLD }(params, fee);

        // enough only for fee
        vm.prank(advertiser);
        vm.expectRevert();
        aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
    }

    function test_Native(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        vm.assume(srcAmountLD >= 10 ** 12 && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, srcAmountLD + 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(GAS_CREATE_OFFER, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(
            bEid,
            uint16(IOtcMarketCore.Message.OfferCreated),
            enforcedOptions
        );

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(beneficiary),
            bEid,
            addressToBytes32(address(0)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        uint256 escrowInitialBalance = address(aEscrow).balance;
        uint256 advertiserInitialBalance = advertiser.balance;

        // create an offer
        vm.prank(advertiser);
        (, IOtcMarketCreateOffer.CreateOfferReceipt memory receipt) = aOtcMarket.createOffer{
            value: fee.nativeFee + srcAmountLD
        }(params, fee);
        uint256 amountLD = receipt.srcAmountLD;

        // should reduce advertiser balance
        // (compare up to 1 percent because the gas for the function call is not taken into consideration)
        assertApproxEqRel(
            advertiser.balance,
            advertiserInitialBalance - (fee.nativeFee + amountLD),
            0.01e18,
            "advertiser balance"
        );

        // should increase escrow balance
        assertEq(address(aEscrow).balance, escrowInitialBalance + amountLD, "escrow balance");
    }
}
