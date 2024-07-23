// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { CalldataBytesLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/CalldataBytesLib.sol";

import { Transfer } from "./libs/Transfer.sol";
import { AmountCast } from "./libs/AmountCast.sol";

import { OtcMarketCore } from "./OtcMarketCore.sol";

/**
 * @dev Module of {OtcMarket} for offer cancelation.
 */
abstract contract OtcMarketCancelOffer is OtcMarketCore {
    using CalldataBytesLib for bytes;

    using AddressCast for address;
    using AddressCast for bytes32;

    using AmountCast for uint256;
    using AmountCast for uint64;

    function cancelOfferAppeal(
        CancelOfferParams calldata _params,
        MessagingFee calldata _fee,
    )   public
        payable
        virtual
        override {
        _validateCancelOfferAppeal(_params, addressToBytes32(msg.sender));

        Offer storage offer = offers[_params.offerId];

        (bytes memory payload, bytes memory options) = _buildCancelOfferAppealMsgAndOptions(
            offer.dstEid,
            _params,
        );

        msgReceipt = _lzSend(offer.dstEid, payload, options, _fee, payable(msg.sender));
    }

    function quoteCancelOfferAppeal(
        bytes32 _srcSellerAddress,
        CancelOfferParams calldata _params,
        bytes calldata _extraSendOptions, 
        bool _payInLzToken,
    ) public view virtual returns (MessagingFee memory fee, AcceptOfferReceipt memory acceptOfferReceipt) {
        _validateCancelOfferAppeal(_params, _srcSellerAddress); // revert
        Offer storage offer = offers[_params.offerId];

        (bytes memory payload, bytes memory options) = _buildCancelOfferAppealMsgAndOptions(
            offer.dstEid,
            _params,
            _extraSendOptions,
        ); // revert
        fee = _quote(offer.dstEid, payload, options, _payInLzToken);
    }

    function quoteCancelOffer(
        CancelOfferParams calldata _params,
    ) public view virtual returns (MessagingFee memory fee) {
        uint16 srcEid = offers[_params.offerId].srcEid;

        (bytes memory payload, bytes memory options) = _buildCancelOfferMsgAndOptions(
            _params.offerId,
            srcEid
        ); // revert
        fee = _quote(srcEid, payload, options, false);
    }

    function _validateCancelOfferAppeal(CancelOfferParams calldata _params, bytes32 srcSellerAddress) internal view virtual {
        Offer storage offer = offers[_params.offerId];

        if (offer.srcAmountSD == 0) {
            revert NonexistentOffer(_params.offerId);
        }
        if (eid != offer.srcEid) {
            revert InvalidEid(eid, offer.srcEid);
        }
        if (offer.srcSeller != srcSellerAddress) {
            revert OnlySeller(offer.srcSeller, srcSellerAddress);
        }
    }

    function _buildCancelOfferAppealMsgAndOptions(
        uint32 _dstEid,
        CancelOfferParams calldata _params,
        bytes calldata _extraSendOptions,
    ) internal view virtual returns (bytes memory payload, bytes memory options){
        bytes memory msgPayload = abi.encodePacked(
            _params.offerId,
            _returnFee
        );
        payload = abi.encodePacked(Message.OfferCancelAppeal, msgPayload);

        bytes enforced = enforcedOptions[dstEid][uint16(Message.OfferCancelAppeal)];
        if (enforced.length == 0 || _extraSendOptions.length == 0) {
            revert InvalidOptions(bytes(""));
        }
        options = combineOptions(dstEid, uint16(Message.OfferCancelAppeal), _extraSendOptions);
        
    }

    function _buildCancelOfferMsgAndOptions(
        uint32 _srcEid,
        bytes32 offerId,
    ) internal view virtual returns (bytes memory payload, bytes memory options){
        bytes memory msgPayload = abi.encodePacked(
            offerId,
        );
        payload = abi.encodePacked(Message.OfferCanceled, msgPayload);

        options = enforcedOptions[srcEid][uint16(Message.OfferCanceled)];
        if (options.length == 0) {
            revert InvalidOptions(options);
        }
    }

    function _decodeCancelOffer(
        bytes calldata _payload
    )
        internal
        pure
        virtual
        returns (bytes32 offerId)
    {
        offerId = _payload.toB32(0);
    }

    function _receiveOfferCancelAppeal(bytes calldata _msgPayload) internal virtual override {
        (bytes32 offerId) = _decodeCancelOffer(
            _msgPayload
        );

        Offer storage offer = offers[offerId];

        emit OfferCancelled(offerId);

        
        MessagingFee memory _fee = quoteCancelOffer(CancelOfferParams(offerId));

        (bytes memory payload, bytes memory options) = _buildCancelOfferMsgAndOptions(
            offer.srcEid,
            offerId
        );

        delete offers[offerId];

        _lzSend(offer.dstEid, payload, options, _fee, payable(offer.dstSellerAddress));
    }

    function _receiveOfferCanceled(bytes calldata _msgPayload) internal virtual override{
        (bytes32 offerId) = _decodeCancelOffer(
            _msgPayload
        );

        Offer storage offer = offers[offerId];

        emit OfferCanceled(offerId);

        escrow.transfer(offer.srcTokenAddress.toAddress(), offer.srcSellerAddress.toAddress(), offer.srcAmountSD.toLD(_getDecimalConversionRate(offer.srcTokenAddress.toAddress())));

        delete offer;
    }    
}
