// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { CalldataBytesLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/CalldataBytesLib.sol";

import { Transfer } from "./libs/Transfer.sol";
import { AmountCast } from "./libs/AmountCast.sol";

import { IOtcMarketAcceptOffer } from "./interfaces/IOtcMarketAcceptOffer.sol";
import { OtcMarketCore } from "./OtcMarketCore.sol";

/**
 * @dev Module of {OtcMarket} for offer acceptance.
 */
abstract contract OtcMarketAcceptOffer is IOtcMarketAcceptOffer, OtcMarketCore {
    using CalldataBytesLib for bytes;

    using AddressCast for address;
    using AddressCast for bytes32;

    using AmountCast for uint64;

    function acceptOffer(
        AcceptOfferParams calldata _params,
        MessagingFee calldata _fee
    )
        external
        payable
        virtual
        override
        returns (MessagingReceipt memory msgReceipt, AcceptOfferReceipt memory acceptOfferReceipt)
    {
        _validateAcceptOffer(_params);
        Offer storage offer = offers[_params.offerId];

        address dstTokenAddress = offer.dstTokenAddress.toAddress();
        acceptOfferReceipt = _toDstAmount(_params.srcAmountSD, offer.exchangeRateSD, dstTokenAddress);

        if (dstTokenAddress == address(0) && msg.value < acceptOfferReceipt.dstAmountLD) {
            revert NotEnoughNative(msg.value);
        }

        offer.srcAmountSD -= _params.srcAmountSD;
        bytes32 dstBuyerAddress = msg.sender.toBytes32();
        emit OfferAccepted(_params.offerId, _params.srcAmountSD, _params.srcBuyerAddress, dstBuyerAddress);

        if (offer.srcEid != offer.dstEid) {
            // crosschain offer
            (bytes memory payload, bytes memory options) = _buildAcceptOfferMsgAndOptions(
                dstBuyerAddress,
                offer.srcEid,
                _params
            );
            msgReceipt = _lzSend(offer.srcEid, payload, options, _fee, payable(msg.sender));
        } else {
            // monochain offer
            address srcTokenAddress = offer.srcTokenAddress.toAddress();

            uint256 srcAmountLD = _params.srcAmountSD.toLD(_getDecimalConversionRate(srcTokenAddress));
            escrow.transfer(srcTokenAddress, _params.srcBuyerAddress.toAddress(), srcAmountLD);
        }

        Transfer.transferFrom(dstTokenAddress, treasury, acceptOfferReceipt.feeLD);
        Transfer.transferFrom(
            dstTokenAddress,
            offer.dstSellerAddress.toAddress(),
            acceptOfferReceipt.dstAmountLD - acceptOfferReceipt.feeLD
        );
    }

    function quoteAcceptOffer(
        bytes32 _dstBuyerAddress,
        AcceptOfferParams calldata _params,
        bool _payInLzToken
    ) public view virtual returns (MessagingFee memory fee, AcceptOfferReceipt memory acceptOfferReceipt) {
        _validateAcceptOffer(_params); // revert
        Offer storage offer = offers[_params.offerId];

        if (offer.dstEid != offer.srcEid) {
            (bytes memory payload, bytes memory options) = _buildAcceptOfferMsgAndOptions(
                _dstBuyerAddress,
                offer.srcEid,
                _params
            ); // revert
            fee = _quote(offer.srcEid, payload, options, _payInLzToken);
        } else {
            fee = MessagingFee(0, 0);
        }

        acceptOfferReceipt = _toDstAmount(_params.srcAmountSD, offer.exchangeRateSD, offer.dstTokenAddress.toAddress()); // revert
    }

    function _validateAcceptOffer(AcceptOfferParams calldata _params) internal view virtual {
        Offer storage offer = offers[_params.offerId];

        if (offer.exchangeRateSD == 0) {
            revert NonexistentOffer(_params.offerId);
        }
        if (eid != offer.dstEid) {
            revert InvalidEid(eid, offer.dstEid);
        }
        if (offer.srcAmountSD < _params.srcAmountSD) {
            revert ExcessiveAmount(offer.srcAmountSD, _params.srcAmountSD);
        }
    }

    function _toDstAmount(
        uint64 _srcAmountSD,
        uint64 _exchangeRateSD,
        address _tokenAddress
    ) internal view virtual returns (AcceptOfferReceipt memory acceptOfferReceipt) {
        uint256 dstDecimalConversionRate = _getDecimalConversionRate(_tokenAddress);

        uint256 dstAmountLD = (uint256(_srcAmountSD) * uint256(_exchangeRateSD) * dstDecimalConversionRate) /
            (10 ** SHARED_DECIMALS);

        uint256 feeLD = dstAmountLD / FEE;
        if (feeLD == 0) {
            revert InvalidPricing(_srcAmountSD, _exchangeRateSD);
        }

        acceptOfferReceipt = AcceptOfferReceipt(dstAmountLD, feeLD);
    }

    function _buildAcceptOfferMsgAndOptions(
        bytes32 _dstBuyerAddress,
        uint32 _srcEid,
        AcceptOfferParams calldata _params
    ) internal view virtual returns (bytes memory payload, bytes memory options) {
        bytes memory msgPayload = abi.encodePacked(
            _params.offerId,
            _params.srcAmountSD,
            _params.srcBuyerAddress,
            _dstBuyerAddress
        );
        payload = abi.encodePacked(Message.OfferAccepted, msgPayload);

        options = enforcedOptions[_srcEid][uint16(Message.OfferAccepted)];
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
        address srcTokenAddress = offer.srcTokenAddress.toAddress();

        offer.srcAmountSD -= srcAmountSD;
        emit OfferAccepted(offerId, srcAmountSD, srcBuyerAddress, dstBuyerAddress);

        uint256 srcAmountLD = srcAmountSD.toLD(_getDecimalConversionRate(srcTokenAddress));
        escrow.transfer(srcTokenAddress, srcBuyerAddress.toAddress(), srcAmountLD);
    }
}
