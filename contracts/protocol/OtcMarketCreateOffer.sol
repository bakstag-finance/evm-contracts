// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { CalldataBytesLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/CalldataBytesLib.sol";

import { Transfer } from "./libs/Transfer.sol";
import { AmountCast } from "./libs/AmountCast.sol";

import { IOtcMarketCreateOffer } from "./interfaces/IOtcMarketCreateOffer.sol";
import { OtcMarketCore } from "./OtcMarketCore.sol";

/**
 * @dev Module of {OtcMarket} for offer creation.
 */
abstract contract OtcMarketCreateOffer is IOtcMarketCreateOffer, OtcMarketCore {
    using CalldataBytesLib for bytes;

    using AddressCast for address;
    using AddressCast for bytes32;

    using AmountCast for uint256;
    using AmountCast for uint64;

    function createOffer(
        CreateOfferParams calldata _params,
        MessagingFee calldata _fee
    )
        external
        payable
        virtual
        override
        returns (MessagingReceipt memory msgReceipt, CreateOfferReceipt memory createOfferReceipt)
    {
        bytes32 srcSellerAddress = msg.sender.toBytes32();
        address srcTokenAddress = _params.srcTokenAddress.toAddress();

        (uint64 srcAmountSD, uint256 srcAmountLD) = _removeDust(_params.srcAmountLD, srcTokenAddress);
        _validatePricing(srcAmountSD, _params.exchangeRateSD);
        if (srcTokenAddress == address(0) && msg.value < srcAmountLD) {
            revert NotEnoughNative(msg.value);
        }

        bytes32 offerId = hashOffer(
            srcSellerAddress,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            _params.exchangeRateSD
        );
        if (offers[offerId].exchangeRateSD != 0) {
            revert OfferAlreadyExists(offerId);
        }

        offers[offerId] = Offer(
            srcSellerAddress,
            _params.dstSellerAddress,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            srcAmountSD,
            _params.exchangeRateSD
        );
        emit OfferCreated(offerId, offers[offerId]);

        if (eid != _params.dstEid) {
            // crosschain offer
            (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(offerId, offers[offerId]);
            msgReceipt = _lzSend(_params.dstEid, payload, options, _fee, payable(msg.sender));
        }

        createOfferReceipt = CreateOfferReceipt(offerId, srcAmountLD);

        Transfer.transferFrom(srcTokenAddress, msg.sender, address(escrow), srcAmountLD);
    }

    function quoteCreateOffer(
        bytes32 _srcSellerAddress,
        CreateOfferParams calldata _params,
        bool _payInLzToken
    ) public view virtual override returns (MessagingFee memory fee, CreateOfferReceipt memory createOfferReceipt) {
        (uint64 srcAmountSD, uint256 srcAmountLD) = _removeDust(
            _params.srcAmountLD,
            _params.srcTokenAddress.toAddress()
        );
        _validatePricing(srcAmountSD, _params.exchangeRateSD); // revert

        bytes32 offerId = hashOffer(
            _srcSellerAddress,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            _params.exchangeRateSD
        );
        if (offers[offerId].exchangeRateSD != 0) {
            revert OfferAlreadyExists(offerId);
        } // revert

        if (_params.dstEid != eid) {
            (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(
                offerId,
                Offer(
                    _srcSellerAddress,
                    _params.dstSellerAddress,
                    eid,
                    _params.dstEid,
                    _params.srcTokenAddress,
                    _params.dstTokenAddress,
                    srcAmountSD,
                    _params.exchangeRateSD
                )
            ); // revert

            fee = _quote(_params.dstEid, payload, options, _payInLzToken);
        } else {
            fee = MessagingFee(0, 0);
        }
        createOfferReceipt = CreateOfferReceipt(offerId, srcAmountLD);
    }

    function _validatePricing(uint64 _srcAmountSD, uint64 _exchangeRateSD) internal view virtual {
        if (_srcAmountSD == 0 || _exchangeRateSD == 0) {
            revert InvalidPricing(_srcAmountSD, _exchangeRateSD);
        }
    }

    function _removeDust(
        uint256 _amountLD,
        address _tokenAddress
    ) private view returns (uint64 amountSD, uint256 amountLD) {
        uint256 srcDecimalConversionRate = _getDecimalConversionRate(_tokenAddress);

        amountSD = _amountLD.toSD(srcDecimalConversionRate);
        amountLD = amountSD.toLD(srcDecimalConversionRate);
    }

    function _buildCreateOfferMsgAndOptions(
        bytes32 _offerId,
        Offer memory _offer
    ) internal view virtual returns (bytes memory payload, bytes memory options) {
        bytes memory msgPayload = abi.encodePacked(
            _offerId,
            _offer.srcSellerAddress,
            _offer.dstSellerAddress,
            _offer.srcEid,
            _offer.dstEid,
            _offer.srcTokenAddress,
            _offer.dstTokenAddress,
            _offer.srcAmountSD,
            _offer.exchangeRateSD
        );
        payload = abi.encodePacked(Message.OfferCreated, msgPayload);

        options = enforcedOptions[_offer.dstEid][uint16(Message.OfferCreated)];
        if (options.length == 0) {
            revert InvalidOptions(options);
        }
    }

    function _decodeOfferCreated(
        bytes calldata _payload
    )
        internal
        pure
        virtual
        returns (
            bytes32 offerId,
            bytes32 srcSellerAddress,
            bytes32 dstSellerAddress,
            uint32 srcEid,
            uint32 dstEid,
            bytes32 srcTokenAddress,
            bytes32 dstTokenAddress,
            uint64 srcAmountSD,
            uint64 exchangeRateSD
        )
    {
        offerId = _payload.toB32(0);
        srcSellerAddress = _payload.toB32(32);
        dstSellerAddress = _payload.toB32(64);
        srcEid = _payload.toU32(96);
        dstEid = _payload.toU32(100);
        srcTokenAddress = _payload.toB32(104);
        dstTokenAddress = _payload.toB32(136);
        srcAmountSD = _payload.toU64(168);
        exchangeRateSD = _payload.toU64(176);
    }

    function _receiveOfferCreated(bytes calldata _msgPayload) internal virtual override {
        (
            bytes32 offerId,
            bytes32 srcSellerAddress,
            bytes32 dstSellerAddress,
            uint32 srcEid,
            uint32 dstEid,
            bytes32 srcTokenAddress,
            bytes32 dstTokenAddress,
            uint64 srcAmountSD,
            uint64 exchangeRateSD
        ) = _decodeOfferCreated(_msgPayload);

        Offer memory _offer = Offer(
            srcSellerAddress,
            dstSellerAddress,
            srcEid,
            dstEid,
            srcTokenAddress,
            dstTokenAddress,
            srcAmountSD,
            exchangeRateSD
        );

        offers[offerId] = _offer;
        emit OfferCreated(offerId, _offer);
    }
}
