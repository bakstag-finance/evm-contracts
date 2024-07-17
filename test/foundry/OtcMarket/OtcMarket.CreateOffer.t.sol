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

import { AmountCast } from "../../../contracts/protocol/libs/AmountCast.sol";

import { IOtcMarketCore } from "../../../contracts/protocol/interfaces/IOtcMarketCore.sol";
import { IOtcMarketCreateOffer } from "../../../contracts/protocol/interfaces/IOtcMarketCreateOffer.sol";
import { IOtcMarketAcceptOffer } from "../../../contracts/protocol/interfaces/IOtcMarketAcceptOffer.sol";

import { Escrow } from "../../../contracts/protocol/Escrow.sol";

contract CreateOffer is OtcMarketTestHelper {
    using OptionsBuilder for bytes;

    using AmountCast for uint256;
    using AmountCast for uint64;

    uint256 public constant SRC_AMOUNT_LD = 1 ether; // 1 ERC20 token
    uint64 public constant EXCHANGE_RATE_SD = 15 * 10 ** 5; // 1.5 dst/src
    uint256 public constant DST_DECIMAL_CONVERSION_RATE = 10 ** 12; // e.g. ERC20

    function testFuzz_EmitOfferCreated(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

        vm.assume(srcAmountLD >= srcDecimalConversionRate && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

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

        assertEq(offer.srcSellerAddress, addressToBytes32(srcSellerAddress), "srcSellerAddress");
        assertEq(offer.dstSellerAddress, addressToBytes32(dstSellerAddress), "dstSellerAddress");
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

        uint64 srcAmountSD = srcAmountLD.toSD(srcDecimalConversionRate);

        // should store offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        (
            bytes32 aAdversiter,
            bytes32 adstSellerAddress,
            uint32 aSrcEid,
            uint32 aDstEid,
            bytes32 aSrcTokenAddress,
            bytes32 aDstTokenAddress,
            uint64 aSrcAmountSD,
            uint64 aExchangeRateSD
        ) = aOtcMarket.offers(receipt.offerId);

        assertEq(aAdversiter, addressToBytes32(srcSellerAddress), "srcSellerAddress");
        assertEq(adstSellerAddress, addressToBytes32(dstSellerAddress), "dstSellerAddress");
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

        // should update balances
        uint256 srcSellerAddressInitialBalance = srcAmountLD;
        uint256 escrowInitialBalance = ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow()));

        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        uint256 srcSellerAddressUpdatedBalance = ERC20(address(aToken)).balanceOf(srcSellerAddress);
        uint256 escrowUpdatedBalance = ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow()));

        assertEq(
            srcSellerAddressUpdatedBalance,
            srcSellerAddressInitialBalance - receipt.srcAmountLD,
            "srcSellerAddress balance"
        );
        assertEq(escrowUpdatedBalance, escrowInitialBalance + receipt.srcAmountLD, "escrow balance");
    }

    function test_RevertOn_InvalidPricing() public {
        vm.deal(srcSellerAddress, 10 ether);

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
                addressToBytes32(dstSellerAddress),
                bEid,
                addressToBytes32(address(aToken)),
                addressToBytes32(address(bToken)),
                0,
                EXCHANGE_RATE_SD
            );

            vm.expectRevert(abi.encodeWithSelector(IOtcMarketCore.InvalidPricing.selector, 0, EXCHANGE_RATE_SD));
            aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);
        }

        // invalid exchange rate
        {
            uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

            // quote fee
            IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
                addressToBytes32(dstSellerAddress),
                bEid,
                addressToBytes32(address(aToken)),
                addressToBytes32(address(bToken)),
                SRC_AMOUNT_LD,
                0
            );

            vm.expectRevert(
                abi.encodeWithSelector(
                    IOtcMarketCore.InvalidPricing.selector,
                    SRC_AMOUNT_LD.toSD(srcDecimalConversionRate),
                    0
                )
            );
            aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);
        }
    }

    function test_RevertIf_OfferAlreadyExists() public {
        // create an offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(SRC_AMOUNT_LD, EXCHANGE_RATE_SD);

        vm.deal(srcSellerAddress, 10 ether);

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
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        vm.expectRevert(abi.encodeWithSelector(IOtcMarketCreateOffer.OfferAlreadyExists.selector, receipt.offerId));
        aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);
    }

    function testFuzz_ReceiveOfferCreated(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());

        vm.assume(srcAmountLD >= srcDecimalConversionRate && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

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

            assertEq(offer.srcSellerAddress, addressToBytes32(srcSellerAddress), "srcSellerAddress");
            assertEq(offer.dstSellerAddress, addressToBytes32(dstSellerAddress), "dstSellerAddress");
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
                bytes32 bdstSellerAddress,
                uint32 bSrcEid,
                uint32 bDstEid,
                bytes32 bSrcTokenAddress,
                bytes32 bDstTokenAddress,
                uint64 bSrcAmountSD,
                uint64 bExchangeRateSD
            ) = bOtcMarket.offers(receipt.offerId);

            assertEq(bAdversiter, addressToBytes32(srcSellerAddress), "srcSellerAddress");
            assertEq(bdstSellerAddress, addressToBytes32(dstSellerAddress), "dstSellerAddress");
            assertEq(bSrcEid, aEid, "srcEid");
            assertEq(bDstEid, bEid, "dstEid");
            assertEq(bSrcTokenAddress, addressToBytes32(address(aToken)), "srcTokenAddress");
            assertEq(bDstTokenAddress, addressToBytes32(address(bToken)), "dstTokenAddress");
            assertEq(bSrcAmountSD, srcAmountSD, "srcAmountSD");
            assertEq(bExchangeRateSD, exchangeRateSD, "exchangeRateSD");
        }
    }

    function test_RevertOn_InsufficientValue() public {
        vm.deal(srcSellerAddress, 10 ether);

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
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(0)),
            addressToBytes32(address(bToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);

        // enough only for srcAmountLD
        vm.prank(srcSellerAddress);
        vm.expectRevert();
        aOtcMarket.createOffer{ value: SRC_AMOUNT_LD }(params, fee);

        // enough only for fee
        vm.prank(srcSellerAddress);
        vm.expectRevert();
        aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
    }

    function testFuzz_NativeUpdateBalances(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        vm.assume(srcAmountLD >= 10 ** 12 && srcAmountLD <= type(uint64).max && exchangeRateSD > 0);

        vm.deal(srcSellerAddress, srcAmountLD + 10 ether);

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
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(0)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);

        uint256 escrowInitialBalance = address(aOtcMarket.escrow()).balance;
        uint256 srcSellerAddressInitialBalance = srcSellerAddress.balance;

        // create an offer
        vm.prank(srcSellerAddress);
        (, IOtcMarketCreateOffer.CreateOfferReceipt memory receipt) = aOtcMarket.createOffer{
            value: fee.nativeFee + srcAmountLD
        }(params, fee);
        uint256 amountLD = receipt.srcAmountLD;

        // should reduce srcSellerAddress balance
        // (compare up to 1 percent because the gas for the function call is not taken into consideration)
        assertApproxEqRel(
            srcSellerAddress.balance,
            srcSellerAddressInitialBalance - (fee.nativeFee + amountLD),
            0.01e18,
            "srcSellerAddress balance"
        );

        // should increase escrow balance
        assertEq(address(aOtcMarket.escrow()).balance, escrowInitialBalance + amountLD, "escrow balance");
    }

    function test_RevertOn_InvalidOptions() public {
        vm.deal(srcSellerAddress, 10 ether);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, bytes("")));
        aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);
    }

    function test_RevertOn_InvalidDecimals() public {
        vm.deal(srcSellerAddress, 10 ether);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(xToken)),
            addressToBytes32(address(bToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        vm.expectRevert();
        aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);
    }
}
