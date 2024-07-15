// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

// OtcMarket imports
import { MyToken } from "../../../contracts/token/MyToken.sol";
import { MyTokenSmallDecimals } from "../../../contracts/token/MyTokenSmallDecimals.sol";

import { OtcMarket } from "../../../contracts/protocol/OtcMarket.sol";
import { Escrow } from "../../../contracts/protocol/Escrow.sol";

contract OtcMarketTestHelper is TestHelperOz5 {
    uint32 public aEid = 1;
    uint32 public bEid = 2;
    uint32 public cEid = 3;

    OtcMarket public aOtcMarket;
    OtcMarket public bOtcMarket;
    OtcMarket public cOtcMarket;

    Escrow public aEscrow;
    Escrow public bEscrow;
    Escrow public cEscrow;

    MyTokenSmallDecimals public xToken; // token with 4 decimals (< 6 decimals)
    MyToken public aToken;
    MyToken public bToken;

    uint128 public constant GAS_CREATE_OFFER = 180000;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        aEscrow = new Escrow(address(this));
        bEscrow = new Escrow(address(this));
        cEscrow = new Escrow(address(this));

        aOtcMarket = new OtcMarket(address(aEscrow), address(this), address(endpoints[aEid]), address(this));
        bOtcMarket = new OtcMarket(address(bEscrow), address(this), address(endpoints[bEid]), address(this));
        cOtcMarket = new OtcMarket(address(cEscrow), address(this), address(endpoints[cEid]), address(this));

        aEscrow.transferOwnership(address(aOtcMarket));
        bEscrow.transferOwnership(address(bOtcMarket));
        cEscrow.transferOwnership(address(cOtcMarket));

        xToken = new MyTokenSmallDecimals(address(this));
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
}
