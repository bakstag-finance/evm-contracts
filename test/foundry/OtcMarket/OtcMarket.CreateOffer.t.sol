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
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        uint64 srcAmountSD = srcAmountLD.toSD(srcDecimalConversionRate);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));

        // should emit OfferCreated
        vm.recordLogs();
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        bytes32 signature = keccak256(
            "OfferCreated(bytes32,(bytes32,bytes32,uint32,uint32,bytes32,bytes32,uint64,uint64))"
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();

        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == signature) {
                Vm.Log memory offerCreatedLog = entries[i];

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
        }
    }

    function testFuzz_StoreOffer(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        uint64 srcAmountSD = srcAmountLD.toSD(srcDecimalConversionRate);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));

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
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));

        uint256 srcSellerInitialBalance = srcAmountLD;
        uint256 srcEscrowInitialBalance = ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow()));

        // should update balances
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        uint256 srcSellerUpdatedBalance = ERC20(address(aToken)).balanceOf(srcSellerAddress);
        uint256 srcEscrowUpdatedBalance = ERC20(address(aToken)).balanceOf(address(aOtcMarket.escrow()));

        assertEq(srcSellerUpdatedBalance, srcSellerInitialBalance - receipt.srcAmountLD, "srcSeller balance");
        assertEq(srcEscrowUpdatedBalance, srcEscrowInitialBalance + receipt.srcAmountLD, "srcEscrow balance");
    }

    function test_RevertOn_InvalidPricing() public {
        _prepare_create_offer(SRC_AMOUNT_LD);

        // invalid source amount
        {
            // quote fee should revert with InvalidPricing
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

            // quote fee should revert with InvalidPricing
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

    function testFuzz_ReceiveOfferCreated(uint256 srcAmountLD, uint64 exchangeRateSD) public {
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        uint64 srcAmountSD = srcAmountLD.toSD(srcDecimalConversionRate);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));

        // create an offer on aOtcMarket
        vm.recordLogs();
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(srcAmountLD, exchangeRateSD);

        // verify that OfferCreated event was emitted
        {
            bytes32 signature = keccak256(
                "OfferCreated(bytes32,(bytes32,bytes32,uint32,uint32,bytes32,bytes32,uint64,uint64))"
            );
            Vm.Log[] memory entries = vm.getRecordedLogs();

            for (uint i = 0; i < entries.length; i++) {
                if (entries[i].topics[0] == signature) {
                    Vm.Log memory offerCreatedLog = entries[i];

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
            }
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

    function test_RevertIf_OfferAlreadyExists() public {
        // create an offer
        IOtcMarketCreateOffer.CreateOfferReceipt memory receipt = _create_offer(SRC_AMOUNT_LD, EXCHANGE_RATE_SD);

        // quote fee should revert with OfferAlreadyExists
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

    function test_RevertIf_NotEnoughNative() public {
        _prepare_create_offer(SRC_AMOUNT_LD);

        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(0)),
            addressToBytes32(address(bToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        // quote fee
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
        uint256 srcDecimalConversionRate = 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.SHARED_DECIMALS());
        srcAmountLD = bound(srcAmountLD, srcDecimalConversionRate, type(uint64).max);
        exchangeRateSD = uint64(bound(exchangeRateSD, 1, type(uint64).max));

        _prepare_create_offer(srcAmountLD);

        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(0)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );
        uint256 srcSellerInitialBalance = srcSellerAddress.balance;
        uint256 srcEscrowInitialBalance = address(aOtcMarket.escrow()).balance;

        // quote fee
        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);

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
            srcSellerInitialBalance - (fee.nativeFee + amountLD),
            0.01e18,
            "srcSeller balance"
        );

        // should increase escrow balance
        assertEq(address(aOtcMarket.escrow()).balance, srcEscrowInitialBalance + amountLD, "srcEscrow balance");
    }

    function test_RevertOn_InvalidOptions() public {
        vm.deal(srcSellerAddress, 10 ether);

        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        // quote should revert with InvalidOptions
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, bytes("")));
        aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);
    }

    function test_RevertOn_InvalidDecimals() public {
        vm.deal(srcSellerAddress, 10 ether);

        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(xToken)),
            addressToBytes32(address(bToken)),
            SRC_AMOUNT_LD,
            EXCHANGE_RATE_SD
        );

        // quote should revert
        vm.expectRevert();
        aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);
    }
}
