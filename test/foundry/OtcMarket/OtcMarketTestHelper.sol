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

    uint128 public constant GAS_CREATE_OFFER = 190000;
    uint128 public constant GAS_ACCEPT_OFFER = 100000;

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

    function _prepare_create_offer(uint256 srcAmountLD) public {
        vm.deal(srcSellerAddress, 10 ether + srcAmountLD);

        // set enforced options for a
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

        // mint src token
        aToken.mint(srcSellerAddress, srcAmountLD);

        // approve aOtcMarket to spend src token
        vm.prank(srcSellerAddress);
        aToken.approve(address(aOtcMarket), srcAmountLD);
    }

    function _create_offer(
        uint256 srcAmountLD,
        uint64 exchangeRateSD
    ) internal returns (IOtcMarketCreateOffer.CreateOfferReceipt memory receipt) {
        _prepare_create_offer(srcAmountLD);

        // quote fee
        IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
            addressToBytes32(dstSellerAddress),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);

        // create an offer
        vm.prank(srcSellerAddress);
        (, receipt) = aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);

        // deliver offer created message to bOtcMarket
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));
    }

    function _prepare_accept_offer(
        uint256 srcAmountLD,
        uint64 exchangeRateSD
    ) public returns (IOtcMarketCreateOffer.CreateOfferReceipt memory createOfferReceipt) {
        createOfferReceipt = _create_offer(srcAmountLD, exchangeRateSD);

        vm.deal(dstBuyerAddress, 10 ether);

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
    }

    // function _create_offer_native(
    //     uint256 srcAmountLD,
    //     uint64 exchangeRateSD
    // ) internal returns (IOtcMarketCreateOffer.CreateOfferReceipt memory receipt) {
    //     vm.deal(srcSellerAddress, srcAmountLD + 10 ether);

    //     // set enforced options for a
    //     bytes memory enforcedOptions = OptionsBuilder
    //         .newOptions()
    //         .addExecutorLzReceiveOption(GAS_CREATE_OFFER, 0)
    //         .addExecutorOrderedExecutionOption();
    //     EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
    //     enforcedOptionsArray[0] = EnforcedOptionParam(
    //         bEid,
    //         uint16(IOtcMarketCore.Message.OfferCreated),
    //         enforcedOptions
    //     );

    //     aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

    //     // quote fee
    //     IOtcMarketCreateOffer.CreateOfferParams memory params = IOtcMarketCreateOffer.CreateOfferParams(
    //         addressToBytes32(dstSellerAddress),
    //         bEid,
    //         addressToBytes32(address(0)),
    //         addressToBytes32(address(0)),
    //         srcAmountLD,
    //         exchangeRateSD
    //     );

    //     (MessagingFee memory fee, ) = aOtcMarket.quoteCreateOffer(addressToBytes32(srcSellerAddress), params, false);

    //     // create an offer
    //     vm.prank(srcSellerAddress);
    //     (, receipt) = aOtcMarket.createOffer{ value: fee.nativeFee + srcAmountLD }(params, fee);
    // }

    function _accept_offer(
        bytes32 offerId,
        uint256 srcAmountSD
    ) internal returns (IOtcMarketAcceptOffer.AcceptOfferReceipt memory receipt) {
        IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
            offerId,
            uint64(srcAmountSD),
            addressToBytes32(srcBuyerAddress)
        );

        (MessagingFee memory fee, IOtcMarketAcceptOffer.AcceptOfferReceipt memory quoteReceipt) = bOtcMarket
            .quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);

        bToken.mint(dstBuyerAddress, quoteReceipt.dstAmountLD);
        vm.prank(dstBuyerAddress);
        bToken.approve(address(bOtcMarket), quoteReceipt.dstAmountLD);

        // accept offer
        vm.prank(dstBuyerAddress);
        (, receipt) = bOtcMarket.acceptOffer{ value: fee.nativeFee }(params, fee);
    }

    // function _accept_offer_native(
    //     bytes32 offerId,
    //     uint256 srcAmountSD
    // ) internal returns (IOtcMarketAcceptOffer.AcceptOfferReceipt memory receipt) {
    //     // set enforced options for b
    //     bytes memory enforcedOptions = OptionsBuilder
    //         .newOptions()
    //         .addExecutorLzReceiveOption(GAS_ACCEPT_OFFER, 0)
    //         .addExecutorOrderedExecutionOption();
    //     EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
    //     enforcedOptionsArray[0] = EnforcedOptionParam(
    //         aEid,
    //         uint16(IOtcMarketCore.Message.OfferAccepted),
    //         enforcedOptions
    //     );

    //     bOtcMarket.setEnforcedOptions(enforcedOptionsArray);

    //     IOtcMarketAcceptOffer.AcceptOfferParams memory params = IOtcMarketAcceptOffer.AcceptOfferParams(
    //         offerId,
    //         uint64(srcAmountSD),
    //         addressToBytes32(srcBuyerAddress)
    //     );

    //     (MessagingFee memory fee, IOtcMarketAcceptOffer.AcceptOfferReceipt memory quoteReceipt) = bOtcMarket
    //         .quoteAcceptOffer(addressToBytes32(dstBuyerAddress), params, false);

    //     // address of buyer on destinantion chain
    //     vm.deal(dstBuyerAddress, quoteReceipt.dstAmountLD + 10 ether);
    //     // accept offer
    //     vm.prank(dstBuyerAddress);
    //     (, receipt) = bOtcMarket.acceptOffer{ value: quoteReceipt.dstAmountLD + fee.nativeFee }(params, fee);
    // }
}
