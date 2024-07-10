// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

import { OtcMarketCore } from "./OtcMarketCore.sol";
import "./Utils.sol";

/**
 * @dev Module of {OtcMarket} for offer creation.
 */
abstract contract OtcMarketCreateOffer is OtcMarketCore {
    function createOffer(
        bytes32 _beneficiary,
        uint32 _dstEid,
        bytes32 _srcTokenAddress,
        bytes32 _dstTokenAddress,
        uint256 _srcAmountLD,
        uint64 _exchangeRateSD,
        bytes calldata _extraOptions // Additional advertiser LZ options
    ) public payable virtual override returns (MessagingReceipt memory msgReceipt, bytes32 newOfferId) {
        address _advertiser = msg.sender;
        bytes32 advertiser = addressToBytes32(_advertiser);

        address srcTokenAddress = bytes32ToAddress(_srcTokenAddress);
        uint256 decimalConversionRate = 10 ** (ERC20(srcTokenAddress).decimals() - sharedDecimals);
        uint64 srcAmountSD = toSD(_srcAmountLD, decimalConversionRate);
        uint256 srcAmountLD = toLD(srcAmountSD, decimalConversionRate); // remove dust

        newOfferId = hashOffer(advertiser, eid, _dstEid, _srcTokenAddress, _dstTokenAddress, _exchangeRateSD);
        if (offers[newOfferId].advertiser != bytes32("")) {
            revert OfferAlreadyExists(newOfferId);
        }

        offers[newOfferId] = Offer(
            advertiser,
            _beneficiary,
            eid,
            _dstEid,
            _srcTokenAddress,
            _dstTokenAddress,
            srcAmountSD,
            _exchangeRateSD
        );
        emit OfferCreated(
            newOfferId,
            advertiser,
            _beneficiary,
            eid,
            _dstEid,
            _srcTokenAddress,
            _dstTokenAddress,
            srcAmountSD,
            _exchangeRateSD
        );
        
        ERC20(srcTokenAddress).transferFrom(_advertiser, address(this), srcAmountLD);

        bytes memory messagePayload = abi.encodePacked(
            newOfferId,
            advertiser,
            _beneficiary,
            eid,
            _dstEid,
            _srcTokenAddress,
            _dstTokenAddress,
            srcAmountSD,
            _exchangeRateSD
        );
        bytes memory payload = abi.encodePacked(Message.OfferCreated, messagePayload);

        // Combine the advertiser _extraOptions with the enforced options via the {OAppOptionsType3}.
        bytes memory options = combineOptions(_dstEid, uint16(Message.OfferCreated), _extraOptions);

        // TODO: deal with MessagingFee
        msgReceipt = _lzSend(_dstEid, payload, options, MessagingFee(msg.value, 0), payable(_advertiser));
    }
}
