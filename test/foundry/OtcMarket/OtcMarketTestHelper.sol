// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

// LZ imports
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

// BF imports
import { Token4D } from "../../../contracts/token/Token4D.sol";
import { Token6D } from "../../../contracts/token/Token6D.sol";
import { Token18D } from "../../../contracts/token/Token18D.sol";

import { IOtcMarketCore } from "../../../contracts/protocol/interfaces/IOtcMarketCore.sol";
import { IOtcMarketCreateOffer } from "../../../contracts/protocol/interfaces/IOtcMarketCreateOffer.sol";
import { IOtcMarketAcceptOffer } from "../../../contracts/protocol/interfaces/IOtcMarketAcceptOffer.sol";

import { OtcMarket } from "../../../contracts/protocol/OtcMarket.sol";
import { Escrow } from "../../../contracts/protocol/Escrow.sol";

contract OtcMarketTestHelper is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 public aEid = 1;
    uint32 public bEid = 2;
    uint32 public cEid = 3;

    OtcMarket public aOtcMarket;
    OtcMarket public bOtcMarket;
    OtcMarket public cOtcMarket;

    Token4D public xToken;
    Token6D public sToken;
    Token18D public aToken;
    Token18D public bToken;

    uint128 public constant GAS_CREATE_OFFER = 180000;
    uint128 public constant GAS_ACCEPT_OFFER = 180000;
    uint128 public constant GAS_CANCEL_OFFER_ORDER = 500000;
    uint128 public constant GAS_CANCEL_OFFER = 300000;

    address public srcBuyerAddress = makeAddr("srcBuyerAddress");
    address public dstBuyerAddress = makeAddr("dstbuyerAddress");
    address public srcSellerAddress = makeAddr("srcSellerAddress");
    address public dstSellerAddress = makeAddr("dstSellerAddress");

    address aTreasury = makeAddr("aTreasury");
    address bTreasury = makeAddr("bTreasury");
    address cTreasury = makeAddr("cTreasury");

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        aOtcMarket = new OtcMarket(aTreasury, address(endpoints[aEid]), address(this));
        bOtcMarket = new OtcMarket(bTreasury, address(endpoints[bEid]), address(this));
        cOtcMarket = new OtcMarket(cTreasury, address(endpoints[cEid]), address(this));

        xToken = new Token4D(address(this));
        sToken = new Token6D(address(this));
        aToken = new Token18D(address(this));
        bToken = new Token18D(address(this));

        // wire a with b
        address[] memory oapps = new address[](2);
        oapps[0] = address(aOtcMarket);
        oapps[1] = address(bOtcMarket);
        this.wireOApps(oapps);

        // wire b with c
        oapps[0] = address(cOtcMarket);
        this.wireOApps(oapps);
    }

    function _set_enforced_create_offer() public {
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
    function _set_enforced_accept_offer() public {
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

    function _set_enforced_cancel_offer(bytes32 offerId) public {
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
            MessagingFee memory returnFee = bOtcMarket.quoteCancelOffer(offerId);

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
    }

    function _prepare_create_offer(uint256 srcAmountLD) public {
        vm.deal(srcSellerAddress, 10 ether + srcAmountLD);

        _set_enforced_create_offer();

        // mint src token
        aToken.mint(srcSellerAddress, srcAmountLD);

        // approve aOtcMarket to spend src token
        vm.prank(srcSellerAddress);
        aToken.approve(address(aOtcMarket), srcAmountLD);
    }

    function _create_offer(
        uint256 srcAmountLD,
        uint64 exchangeRateSD,
        bool native
    ) internal returns (IOtcMarketCreateOffer.CreateOfferReceipt memory receipt) {
        _prepare_create_offer(srcAmountLD);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            native ? addressToBytes32(address(0)) : addressToBytes32(address(aToken)),
            native ? addressToBytes32(address(0)) : addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);

        // create an offer
        vm.prank(srcSellerAddress);
        (, receipt) = aOtcMarket.createOffer{ value: native ? fee.nativeFee + srcAmountLD : fee.nativeFee }(
            params,
            fee
        );

        // deliver offer created message to bOtcMarket
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));
    }

    function _prepare_accept_offer(
        uint256 srcAmountLD,
        uint64 exchangeRateSD,
        bool native
    ) public returns (IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt) {
        createOfferReceipt = _create_offer(srcAmountLD, exchangeRateSD, native);

        vm.deal(dstBuyerAddress, 10 ether);

        // set enforced options for b
        _set_enforced_accept_offer();
    }

    function _accept_offer(
        bytes32 offerId,
        uint256 srcAmountSD,
        bool native
    ) internal returns (IOtcMarketAcceptOffer.AcceptOfferReceipt memory receipt) {
        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            offerId,
            uint64(srcAmountSD),
            addressToBytes32(srcBuyerAddress)
        );

        (MessagingFee memory fee, IOtcMarketAcceptOffer.AcceptOfferReceipt memory quoteReceipt) = bOtcMarket
            .quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);

        if (native) {
            vm.deal(dstBuyerAddress, quoteReceipt.dstAmountLD + 10 ether);
        } else {
            bToken.mint(dstBuyerAddress, quoteReceipt.dstAmountLD);
            vm.prank(dstBuyerAddress);
            bToken.approve(address(bOtcMarket), quoteReceipt.dstAmountLD);
        }

        // accept offer
        vm.prank(dstBuyerAddress);
        (, receipt) = bOtcMarket.acceptOffer{
            value: native ? fee.nativeFee + quoteReceipt.dstAmountLD : fee.nativeFee
        }(params, fee);

        // deliver offer accepted message to aOtcMarket
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));
    }

    function _prepare_cancel_offer(
        uint256 srcAmountLD,
        uint64 exchangeRateSD,
        bool native
    ) internal returns (IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt) {
        createOfferReceipt = _create_offer(srcAmountLD, exchangeRateSD, native);

        _set_enforced_cancel_offer(createOfferReceipt.offerId);
    }

    function _cancel_offer(bytes32 offerId) internal {
        MessagingFee memory returnFee = bOtcMarket.quoteCancelOffer(offerId);
        bytes memory extraSendOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            0,
            uint128(returnFee.nativeFee)
        );

        MessagingFee memory fee = aOtcMarket.quoteCancelOfferOrder(
            addressToBytes32(srcSellerAddress),
            offerId,
            extraSendOptions,
            false
        );

        vm.prank(srcSellerAddress);
        aOtcMarket.cancelOfferOrder{ value: fee.nativeFee }(offerId, fee, extraSendOptions);

        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));
        verifyPackets(aEid, addressToBytes32(address(aOtcMarket)));
    }
}
