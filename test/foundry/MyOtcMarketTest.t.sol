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

        // address[] memory oapps = new address[](2);
        // oapps[0] = address(aOApp);
        // oapps[1] = address(bOApp);
        // this.wireOApps(oapps);
    }

    function test_set_up() public {
        assertEq(aOtcMarket.owner(), address(this));
        assertEq(bOtcMarket.owner(), address(this));
        assertEq(cOtcMarket.owner(), address(this));

        assertEq(address(aOtcMarket.endpoint()), address(endpoints[aEid]));
        assertEq(address(bOtcMarket.endpoint()), address(endpoints[bEid]));
        assertEq(address(cOtcMarket.endpoint()), address(endpoints[cEid]));
    }

    function test_create_offer_delivery() public {
        uint256 amount = 1 ether;
        uint64 exchangeRate = toSD(1 ether, 10 ** 12);
        uint128 gas = 1500000;

        // 1) introduce advertiser and beneficiary
        address advertiser = makeAddr("seller");
        vm.deal(advertiser, 10 ether);

        address beneficiary = makeAddr("beneficiary");

        bytes32 offerId = aOtcMarket.hashOffer(
            addressToBytes32(advertiser),
            aEid,
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            exchangeRate
        );

        uint64 srcAmountSD = toSD(amount, 10 ** ERC20(address(aToken)).decimals() - aOtcMarket.sharedDecimals());

        bytes memory msgPayload = abi.encodePacked(
            offerId,
            addressToBytes32(advertiser),
            addressToBytes32(beneficiary),
            aEid,
            bEid,
            addressToBytes32(address(aToken)),
            addressToBytes32(address(bToken)),
            srcAmountSD,
            exchangeRate
        );
        bytes memory payload = abi.encodePacked(IOtcMarket.Message.OfferCreated, msgPayload);

        // // 2) wire oapps
        // address[] memory oapps = new address[](2);
        // oapps[0] = address(aOtcMarket);
        // oapps[1] = address(bOtcMarket);
        // this.wireOApps(oapps);

        // // 3) set enforced options for a
        // bytes memory enforcedOptions = OptionsBuilder
        //     .newOptions()
        //     .addExecutorLzReceiveOption(gas, 0)
        //     .addExecutorOrderedExecutionOption();
        // EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        // enforcedOptionsArray[0] = EnforcedOptionParam(bEid, uint16(IOtcMarket.Message.OfferCreated), enforcedOptions);

        // aOtcMarket.setEnforcedOptions(enforcedOptionsArray);

        // // 4) mint src token
        // aToken.mint(advertiser, amount);

        // // 5) approve aOtcMarket to spend src token
        // vm.prank(advertiser);
        // aToken.approve(address(aOtcMarket), amount);

        // // 6) quote fee
        // IOtcMarket.CreateOfferParams memory params = IOtcMarket.CreateOfferParams(
        //     addressToBytes32(beneficiary),
        //     bEid,
        //     addressToBytes32(address(aToken)),
        //     addressToBytes32(address(bToken)),
        //     amount,
        //     exchangeRate
        // );

        // MessagingFee memory fee = aOtcMarket.quoteCreateOffer(addressToBytes32(advertiser), params, false);

        // // 7) create an offer
        // vm.prank(advertiser);
        // aOtcMarket.createOffer{ value: fee.nativeFee }(params, fee);

        // // 8) deliver OfferCreated message to bOtcMarket
        // verifyPackets(bEid, addressToBytes32(address(bOtcMarket)));
    }
}
