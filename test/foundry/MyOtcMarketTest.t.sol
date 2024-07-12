// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OtcMarket imports
import { MyOtcMarket } from "../../contracts/OtcMarket/MyOtcMarket.sol";
import { IOtcMarket } from "../../contracts/OtcMarket/IOtcMarket.sol";
import { MyToken } from "../../contracts/MyToken.sol";
import "../../contracts/OtcMarket/Utils.sol";

// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Forge imports
import "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyOAppTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;
    uint32 private cEid = 3;

    MyOtcMarket private aOtcMarket;
    MyOtcMarket private bOtcMarket;
    MyOtcMarket private cOtcMarket;

    MyToken private aToken;
    MyToken private bToken;

    uint256 private MINTED = 1000 ether;

    // address private userA = address(0x1);
    // address private userB = address(0x2);
    // uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        // vm.deal(userA, 1000 ether);
        // vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        aOtcMarket = MyOtcMarket(
            _deployOApp(type(MyOtcMarket).creationCode, abi.encode(address(endpoints[aEid]), address(this)))
        );
        bOtcMarket = MyOtcMarket(
            _deployOApp(type(MyOtcMarket).creationCode, abi.encode(address(endpoints[bEid]), address(this)))
        );
        cOtcMarket = MyOtcMarket(
            _deployOApp(type(MyOtcMarket).creationCode, abi.encode(address(endpoints[cEid]), address(this)))
        );

        aToken = new MyToken(address(this));
        bToken = new MyToken(address(this));

        // wire a with b
        address[] memory oapps = new address[](2);
        oapps[0] = address(aOtcMarket);
        oapps[1] = address(bOtcMarket);
        this.wireOApps(oapps);

        // wire b with c
        oapps[0] = address(cOtcMarket);
        this.wireOApps(oapps);
    }

    function test_set_up() public {
        assertEq(aOtcMarket.owner(), address(this));
        assertEq(bOtcMarket.owner(), address(this));
        assertEq(cOtcMarket.owner(), address(this));

        assertEq(address(aOtcMarket.endpoint()), address(endpoints[aEid]));
        assertEq(address(bOtcMarket.endpoint()), address(endpoints[bEid]));
        assertEq(address(cOtcMarket.endpoint()), address(endpoints[cEid]));
    }

    function _create_offer(uint256 srcAmountLD, uint64 exchangeRateSD, uint128 gas) private returns (bytes32 offerId) {
        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(gas, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(bEid, uint16(IOtcMarket.Message.OfferCreated), enforcedOptions);

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // mint src token
        aToken.mint(advertiser, srcAmountLD);

        // approve aOtcMarket to spend src token
        vm.prank(advertiser);
        aToken.approve(address(aOtcMarket), srcAmountLD);

        // quote fee
        IOtcMarket.CreateOfferParams memory params = IOtcMarket.CreateOfferParams(
            addressToBytes32(beneficiary),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        MessagingFee memory fee = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        // create an offer
        vm.prank(advertiser);
        (, offerId) = aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
    }

    function test_create_offer_success() public {
        uint256 srcAmountLD = 1 ether;
        uint64 exchangeRateSD = toSD(1 ether, 10 ** 12);
        uint128 gas = 1500000;

        address advertiser = makeAddr("seller");
        address beneficiary = makeAddr("beneficiary");

        uint64 srcAmountSD = toSD(srcAmountLD, 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.sharedDecimals()));

        // create an offer on aOtcMarket
        vm.recordLogs();
        bytes32 offerId = _create_offer(srcAmountLD, exchangeRateSD, gas);

        // should emit OfferCreated
        {
            Vm.Log[] memory entries = vm.getRecordedLogs();

            Vm.Log memory offerCreatedLog = entries[3];

            // verify offerId is a topic
            assertEq(offerCreatedLog.topics[1], offerId);

            // assert data
            IOtcMarket.Offer memory offer = abi.decode(offerCreatedLog.data, (IOtcMarket.Offer));

            assertEq(offer.advertiser, addressToBytes32(advertiser), "advertiser");
            assertEq(offer.beneficiary, addressToBytes32(beneficiary), "beneficiary");
            assertEq(offer.srcEid, aEid, "srcEid");
            assertEq(offer.dstEid, bEid, "dstEid");
            assertEq(offer.srcTokenAddress, addressToBytes32(address(aToken)), "srcTokenAddress");
            assertEq(offer.dstTokenAddress, addressToBytes32(address(bToken)), "dstTokenAddress");
            assertEq(offer.srcAmountSD, srcAmountSD, "srcAmountSD");
            assertEq(offer.exchangeRateSD, exchangeRateSD, "exchangeRateSD");
        }

        // should store offer
        {
            (
                bytes32 aAdversiter,
                bytes32 aBeneficiary,
                uint32 aSrcEid,
                uint32 aDstEid,
                bytes32 aSrcTokenAddress,
                bytes32 aDstTokenAddress,
                uint64 aSrcAmountSD,
                uint64 aExchangeRateSD
            ) = aOtcMarket.offers(offerId);

            assertEq(aAdversiter, addressToBytes32(advertiser), "advertiser");
            assertEq(aBeneficiary, addressToBytes32(beneficiary), "beneficiary");
            assertEq(aSrcEid, aEid, "srcEid");
            assertEq(aDstEid, bEid, "dstEid");
            assertEq(aSrcTokenAddress, addressToBytes32(address(aToken)), "srcTokenAddress");
            assertEq(aDstTokenAddress, addressToBytes32(address(bToken)), "dstTokenAddress");
            assertEq(aSrcAmountSD, srcAmountSD, "srcAmountSD");
            assertEq(aExchangeRateSD, exchangeRateSD, "exchangeRateSD");
        }
    }

    function test_create_offer_invalid_pricing() public {
        uint256 srcAmountLD = 0;
        uint64 exchangeRateSD = toSD(1 ether, 10 ** 12);
        uint128 gas = 1500000;

        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(gas, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(bEid, uint16(IOtcMarket.Message.OfferCreated), enforcedOptions);

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // quote fee
        IOtcMarket.CreateOfferParams memory params = IOtcMarket.CreateOfferParams(
            addressToBytes32(beneficiary),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        MessagingFee memory fee = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        // create an offer
        vm.prank(advertiser);
        vm.expectRevert(abi.encodeWithSelector(IOtcMarket.InvalidPricing.selector, srcAmountLD, exchangeRateSD));
        aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
    }

    function test_create_offer_already_exists() public {
        uint256 srcAmountLD = 1 ether;
        uint64 exchangeRateSD = toSD(1 ether, 10 ** 12);
        uint128 gas = 1500000;

        // create an offer
        bytes32 offerId = _create_offer(srcAmountLD, exchangeRateSD, gas);

        // introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        // set enforced options for a
        bytes memory enforcedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(gas, 0)
            .addExecutorOrderedExecutionOption();
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(bEid, uint16(IOtcMarket.Message.OfferCreated), enforcedOptions);

        aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // quote fee
        IOtcMarket.CreateOfferParams memory params = IOtcMarket.CreateOfferParams(
            addressToBytes32(beneficiary),
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            srcAmountLD,
            exchangeRateSD
        );

        MessagingFee memory fee = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        // try to create a dublicate offer
        vm.prank(advertiser);
        vm.expectRevert(abi.encodeWithSelector(IOtcMarket.OfferAlreadyExists.selector, offerId));
        aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);
    }

    function test_receive_offer_created() public {
        uint256 srcAmountLD = 1 ether;
        uint64 exchangeRateSD = toSD(1 ether, 10 ** 12);
        uint128 gas = 1500000;

        address advertiser = makeAddr("seller");
        address beneficiary = makeAddr("beneficiary");

        uint64 srcAmountSD = toSD(srcAmountLD, 10 ** (ERC20(address(aToken)).decimals() - aOtcMarket.sharedDecimals()));

        // create an offer on aOtcMarket
        bytes32 offerId = _create_offer(srcAmountLD, exchangeRateSD, gas);

        // deliver OfferCreated message to bOtcMarket
        vm.recordLogs();
        verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));

        // verify that OfferCreated event was emitted
        {
            Vm.Log[] memory entries = vm.getRecordedLogs();

            Vm.Log memory offerCreatedLog = entries[2];

            // verify offerId is a topic
            assertEq(offerCreatedLog.topics[1], offerId);

            // assert data
            IOtcMarket.Offer memory offer = abi.decode(offerCreatedLog.data, (IOtcMarket.Offer));

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
            ) = bOtcMarket.offers(offerId);

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
}
