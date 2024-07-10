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
        bytes calldata _extraOptions, // Additional advertiser LZ options
        MessagingFee calldata _fee
    ) public payable virtual override returns (MessagingReceipt memory msgReceipt, bytes32 offerId) {
        address _advertiser = msg.sender;
        bytes32 advertiser = addressToBytes32(_advertiser);

        address srcTokenAddress = bytes32ToAddress(_srcTokenAddress);
        uint256 decimalConversionRate = 10 ** (ERC20(srcTokenAddress).decimals() - sharedDecimals);
        uint64 srcAmountSD = toSD(_srcAmountLD, decimalConversionRate);
        uint256 srcAmountLD = toLD(srcAmountSD, decimalConversionRate); // remove dust

        offerId = hashOffer(advertiser, eid, _dstEid, _srcTokenAddress, _dstTokenAddress, _exchangeRateSD);
        if (offers[offerId].advertiser != bytes32("")) {
            revert OfferAlreadyExists(offerId);
        }

        Offer memory offer = Offer(
            advertiser,
            _beneficiary,
            eid,
            _dstEid,
            _srcTokenAddress,
            _dstTokenAddress,
            srcAmountSD,
            _exchangeRateSD
        );

        offers[offerId] = offer;
        emit OfferCreated(
            offerId,
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

        (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(
            offerId,
            offer,
            _extraOptions
        );
        
        msgReceipt = _lzSend(_dstEid, payload, options, _fee, payable(_advertiser));
    }

    function quoteCreateOffer(
        bytes32 _advertiser,
        bytes32 _beneficiary,
        uint32 _dstEid,
        bytes32 _srcTokenAddress,
        bytes32 _dstTokenAddress,
        uint256 _srcAmountLD,
        uint64 _exchangeRateSD,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) public payable virtual returns (MessagingFee memory fee) {
        address srcTokenAddress = bytes32ToAddress(_srcTokenAddress);
        uint256 decimalConversionRate = 10 ** (ERC20(srcTokenAddress).decimals() - sharedDecimals);
        uint64 srcAmountSD = toSD(_srcAmountLD, decimalConversionRate);

        bytes32 offerId = hashOffer(_advertiser, eid, _dstEid, _srcTokenAddress, _dstTokenAddress, _exchangeRateSD);

        (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(
            offerId,
            Offer(
                _advertiser,
                _beneficiary,
                eid,
                _dstEid,
                _srcTokenAddress,
                _dstTokenAddress,
                srcAmountSD,
                _exchangeRateSD
            ),
            _extraOptions
        );

        fee = _quote(_dstEid, payload, options, _payInLzToken);
    }

    function _buildCreateOfferMsgAndOptions(
        bytes32 _offerId,
        Offer memory _offer,
        bytes calldata _extraOptions
    ) internal view virtual returns (bytes memory payload, bytes memory options) {
        bytes memory msgPayload = abi.encodePacked(
            _offerId,
            _offer.advertiser,
            _offer.beneficiary,
            _offer.srcEid,
            _offer.dstEid,
            _offer.srcTokenAddress,
            _offer.dstTokenAddress,
            _offer.srcAmountSD,
            _offer.exchangeRateSD
        );
        payload = abi.encodePacked(Message.OfferCreated, msgPayload);

        // Combine the advertiser _extraOptions with the enforced options via the {OAppOptionsType3}.
        options = combineOptions(_offer.dstEid, uint16(Message.OfferCreated), _extraOptions);
    }
}
