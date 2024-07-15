// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { CalldataBytesLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/CalldataBytesLib.sol";

import { Transfer } from "./libs/Transfer.sol";
import { AmountCast } from "./libs/AmountCast.sol";

import { OtcMarketCore } from "./OtcMarketCore.sol";

/**
 * @dev Module of {OtcMarket} for offer acceptance.
 */
abstract contract OtcMarketAcceptOffer is OtcMarketCore {
    using CalldataBytesLib for bytes;

    using AddressCast for address;
    using AddressCast for bytes32;

    using AmountCast for uint64;

    function acceptOffer(
        AcceptOfferParams calldata _params,
        MessagingFee calldata _fee
    )
        public
        payable
        virtual
        returns (MessagingReceipt memory msgReceipt, AcceptOfferReceipt memory acceptOfferReceipt)
    {
        _validateAcceptOffer(_params);
        Offer storage offer = offers[_params.offerId];

        offer.srcAmountSD -= _params.srcAmountSD;
        emit OfferAccepted(_params.offerId, _params.srcAmountSD, _params.srcBuyerAddress, msg.sender.toBytes32());

        (bytes memory payload, bytes memory options) = _buildAcceptOfferMsgAndOptions(
            _params.srcBuyerAddress,
            offer.dstEid,
            _params
        );
        msgReceipt = _lzSend(offer.dstEid, payload, options, _fee, payable(msg.sender));

        address dstTokenAddress = offer.dstTokenAddress.toAddress();
        acceptOfferReceipt = _toDstAmount(_params.srcAmountSD, offer.exchangeRateSD, dstTokenAddress);

        Transfer.transferFrom(dstTokenAddress, msg.sender, address(treasury), acceptOfferReceipt.feeLD);
        Transfer.transferFrom(
            dstTokenAddress,
            msg.sender,
            offer.dstSellerAddress.toAddress(),
            acceptOfferReceipt.dstAmountLD
        );
    }

    function quoteAcceptOffer(
        AcceptOfferParams calldata _params,
        bool _payInLzToken
    ) public virtual returns (MessagingFee memory fee, AcceptOfferReceipt memory acceptOfferReceipt) {
        Offer storage offer = offers[_params.offerId];

        (bytes memory payload, bytes memory options) = _buildAcceptOfferMsgAndOptions(
            _params.srcBuyerAddress,
            eid,
            _params
        );
        fee = _quote(offer.dstEid, payload, options, _payInLzToken);

        acceptOfferReceipt = _toDstAmount(_params.srcAmountSD, offer.exchangeRateSD, offer.dstTokenAddress.toAddress());
    }

    function _validateAcceptOffer(AcceptOfferParams calldata _params) internal view virtual {
        Offer storage offer = offers[_params.offerId];

        if (offer.srcAmountSD == 0) {
            revert NonexistentOffer(_params.offerId);
        }
        if (eid != offer.dstEid) {
            revert InvalidEid(eid, offer.dstEid);
        }
        if (_params.srcAmountSD == 0) {
            revert InsufficientAmount(1, _params.srcAmountSD);
        }
        if (offer.srcAmountSD < _params.srcAmountSD) {
            revert ExcessiveAmount(offer.srcAmountSD, _params.srcAmountSD);
        }
        if (offer.dstTokenAddress.toAddress() == address(0) && _params.srcAmountSD > msg.value) {
            revert InsufficientValue(_params.srcAmountSD, msg.value);
        }
    }

    function _toDstAmount(
        uint64 _srcAmountSD,
        uint64 _exchangeRateSD,
        address _tokenAddress
    ) internal view virtual returns (AcceptOfferReceipt memory acceptOfferReceipt) {
        uint256 dstAmountLD = (uint256(_srcAmountSD) *
            uint256(_exchangeRateSD) *
            _getDecimalConversionRate(_tokenAddress)) / (10 ** SHARED_DECIMALS);

        uint256 feeLD = dstAmountLD / FEE;

        acceptOfferReceipt = AcceptOfferReceipt(dstAmountLD, feeLD);
    }

    function _buildAcceptOfferMsgAndOptions(
        bytes32 _dstBuyerAddress,
        uint32 _dstEid,
        AcceptOfferParams calldata _params
    ) internal virtual returns (bytes memory payload, bytes memory options) {
        bytes memory msgPayload = abi.encodePacked(
            _params.offerId,
            _params.srcAmountSD,
            _params.srcBuyerAddress,
            _dstBuyerAddress
        );
        payload = abi.encodePacked(Message.OfferCreated, msgPayload);

        options = enforcedOptions[_dstEid][uint16(Message.OfferAccepted)];
        if (options.length == 0) {
            revert InvalidOptions(options);
        }
    }

    function _decodeOfferAccepted(
        bytes calldata _payload
    )
        internal
        pure
        virtual
        returns (bytes32 offerId, uint64 srcAmountSD, bytes32 srcBuyerAddress, bytes32 dstBuyerAddress)
    {
        offerId = _payload.toB32(0);
        srcAmountSD = _payload.toU64(32);
        srcBuyerAddress = _payload.toB32(40);
        dstBuyerAddress = _payload.toB32(72);
    }

    function _receiveOfferAccepted(bytes calldata _msgPayload) internal virtual override {
        (bytes32 offerId, uint64 srcAmountSD, bytes32 srcBuyerAddress, bytes32 dstBuyerAddress) = _decodeOfferAccepted(
            _msgPayload
        );

        Offer storage offer = offers[offerId];

        offer.srcAmountSD -= srcAmountSD;
        emit OfferAccepted(offerId, srcAmountSD, srcBuyerAddress, dstBuyerAddress);

        escrow.transfer(offer.srcTokenAddress.toAddress(), srcBuyerAddress.toAddress(), srcAmountSD);
    }
}
