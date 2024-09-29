// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { CalldataBytesLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/CalldataBytesLib.sol";

import { AmountCast } from "./libs/AmountCast.sol";

import { IOtcMarketCancelOffer } from "./interfaces/IOtcMarketCancelOffer.sol";
import { OtcMarketCore } from "./OtcMarketCore.sol";

/**
 * @dev Module of {OtcMarket} for offer cancelation.
 */
abstract contract OtcMarketCancelOffer is IOtcMarketCancelOffer, OtcMarketCore {
    using CalldataBytesLib for bytes;

    using AddressCast for address;
    using AddressCast for bytes32;

    using AmountCast for uint64;

    function cancelOffer(
        bytes32 _offerId,
        MessagingFee calldata _fee,
        bytes calldata _extraSendOptions
    ) external payable virtual override returns (MessagingReceipt memory msgReceipt) {
        _validateCancelOffer(msg.sender.toBytes32(), _offerId);

        Offer storage offer = offers[_offerId];

        if (offer.srcEid != offer.dstEid) {
            // crosschain offer
            (bytes memory payload, bytes memory options) = _buildCancelOfferOrderMsgAndOptions(
                offer.dstEid,
                _offerId,
                _extraSendOptions
            );
            msgReceipt = _lzSend(offer.dstEid, payload, options, _fee, payable(msg.sender));
        } else {
            // monochain offer
            address srcTokenAddress = offer.srcTokenAddress.toAddress();

            escrow.transfer(
                srcTokenAddress,
                offer.srcSellerAddress.toAddress(),
                offer.srcAmountSD.toLD(_getDecimalConversionRate(srcTokenAddress))
            );

            emit OfferCanceled(_offerId);
            delete offers[_offerId];
        }
    }

    function quoteCancelOfferOrder(
        bytes32 _srcSellerAddress,
        bytes32 _offerId,
        bytes calldata _extraSendOptions,
        bool _payInLzToken
    ) public view virtual override returns (MessagingFee memory fee) {
        _validateCancelOffer(_srcSellerAddress, _offerId); // revert
        Offer storage offer = offers[_offerId];

        (bytes memory payload, bytes memory options) = _buildCancelOfferOrderMsgAndOptions(
            offer.dstEid,
            _offerId,
            _extraSendOptions
        ); // revert
        fee = _quote(offer.dstEid, payload, options, _payInLzToken);
    }

    function quoteCancelOffer(bytes32 _offerId) public view virtual override returns (MessagingFee memory fee) {
        uint32 srcEid = offers[_offerId].srcEid;

        (bytes memory payload, bytes memory options) = _buildCancelOfferMsgAndOptions(srcEid, _offerId); // revert
        fee = _quote(srcEid, payload, options, false);
    }

    function _validateCancelOffer(bytes32 _srcSellerAddress, bytes32 _offerId) internal view virtual {
        Offer storage offer = offers[_offerId];

        if (offer.exchangeRateSD == 0) {
            revert NonexistentOffer(_offerId);
        }
        if (eid != offer.srcEid) {
            revert InvalidEid(offer.srcEid, eid);
        }
        if (offer.srcSellerAddress != _srcSellerAddress) {
            revert OnlySeller(offer.srcSellerAddress, _srcSellerAddress);
        }
    }

    function _buildCancelOfferOrderMsgAndOptions(
        uint32 _dstEid,
        bytes32 _offerId,
        bytes calldata _extraSendOptions
    ) internal view virtual returns (bytes memory payload, bytes memory options) {
        bytes memory msgPayload = abi.encodePacked(_offerId, offers[_offerId].srcEid);
        payload = abi.encodePacked(Message.OfferCancelOrder, msgPayload);

        bytes memory enforced = enforcedOptions[_dstEid][uint16(Message.OfferCancelOrder)];
        if (enforced.length == 0 || _extraSendOptions.length == 0) {
            revert InvalidOptions(bytes(""));
        }
        options = combineOptions(_dstEid, uint16(Message.OfferCancelOrder), _extraSendOptions);
    }

    function _buildCancelOfferMsgAndOptions(
        uint32 _srcEid,
        bytes32 _offerId
    ) internal view virtual returns (bytes memory payload, bytes memory options) {
        bytes memory msgPayload = abi.encodePacked(_offerId);
        payload = abi.encodePacked(Message.OfferCanceled, msgPayload);

        options = enforcedOptions[_srcEid][uint16(Message.OfferCanceled)];
        if (options.length == 0) {
            revert InvalidOptions(options);
        }
    }

    function _decodeCancelOffer(bytes calldata _payload) internal pure virtual returns (bytes32 offerId) {
        offerId = _payload.toB32(0);
    }

    function _receiveOfferCancelOrder(bytes calldata _msgPayload) internal virtual override {
        bytes32 offerId = _decodeCancelOffer(_msgPayload);

        Offer storage offer = offers[offerId];

        MessagingFee memory _fee = quoteCancelOffer(offerId);
        (bytes memory payload, bytes memory options) = _buildCancelOfferMsgAndOptions(offer.srcEid, offerId);
        _lzSend(offer.srcEid, payload, options, _fee, payable(offer.dstSellerAddress.toAddress()));

        emit OfferCanceled(offerId);
        delete offers[offerId];
    }

    function _receiveOfferCanceled(bytes calldata _msgPayload) internal virtual override {
        bytes32 offerId = _decodeCancelOffer(_msgPayload);

        Offer storage offer = offers[offerId];
        address srcTokenAddress = offer.srcTokenAddress.toAddress();

        escrow.transfer(
            srcTokenAddress,
            offer.srcSellerAddress.toAddress(),
            offer.srcAmountSD.toLD(_getDecimalConversionRate(srcTokenAddress))
        );

        emit OfferCanceled(offerId);
        delete offers[offerId];
    }
}
