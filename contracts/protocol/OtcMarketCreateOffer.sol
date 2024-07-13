// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { CalldataBytesLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/CalldataBytesLib.sol";

import { Transfer } from "./libs/Transfer.sol";
import { AmountCast } from "./libs/AmountCast.sol";

import { OtcMarketCore } from "./OtcMarketCore.sol";

/**
 * @dev Module of {OtcMarket} for offer creation.
 */
abstract contract OtcMarketCreateOffer is OtcMarketCore {
    using CalldataBytesLib for bytes;

    using AddressCast for address;
    using AddressCast for bytes32;

    using AmountCast for uint256;
    using AmountCast for uint64;

    function createOffer(
        CreateOfferParams calldata _params,
        MessagingFee calldata _fee
    )
        public
        payable
        virtual
        override
        returns (MessagingReceipt memory msgReceipt, CreateOfferReceipt memory createOfferReceipt)
    {
        bytes32 advertiser = msg.sender.toBytes32();
        address srcTokenAddress = _params.srcTokenAddress.toAddress();

        (uint64 srcAmountSD, uint256 srcAmountLD) = _removeDust(_params.srcAmountLD, srcTokenAddress);
        _validatePricing(srcTokenAddress, srcAmountLD, _params.exchangeRateSD);

        bytes32 offerId = hashOffer(
            advertiser,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            _params.exchangeRateSD
        );
        if (offers[offerId].srcAmountSD != 0) {
            revert OfferAlreadyExists(offerId);
        }

        offers[offerId] = Offer(
            advertiser,
            _params.beneficiary,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            srcAmountSD,
            _params.exchangeRateSD
        );
        emit OfferCreated(offerId, offers[offerId]);

        (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(offerId, offers[offerId]);
        msgReceipt = _lzSend(_params.dstEid, payload, options, _fee, payable(msg.sender));

        createOfferReceipt = CreateOfferReceipt(offerId, srcAmountLD);

        Transfer.transferFrom(srcTokenAddress, msg.sender, address(escrow), srcAmountLD);
    }

    function _validatePricing(address _srcTokenAddress, uint256 _srcAmountLD, uint64 _exchangeRateSD) internal virtual {
        if (_srcAmountLD == 0 || _exchangeRateSD == 0) {
            revert InvalidPricing(_srcAmountLD, _exchangeRateSD);
        }

        if (_srcTokenAddress == address(0) && _srcAmountLD > msg.value) {
            revert InsufficientValue(_srcAmountLD, msg.value);
        }
    }

    function quoteCreateOffer(
        bytes32 _advertiser,
        CreateOfferParams calldata _params,
        bool _payInLzToken
    ) public view virtual override returns (MessagingFee memory fee) {
        (uint64 srcAmountSD, ) = _removeDust(_params.srcAmountLD, _params.srcTokenAddress.toAddress());

        bytes32 offerId = hashOffer(
            _advertiser,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            _params.exchangeRateSD
        );

        (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(
            offerId,
            Offer(
                _advertiser,
                _params.beneficiary,
                eid,
                _params.dstEid,
                _params.srcTokenAddress,
                _params.dstTokenAddress,
                srcAmountSD,
                _params.exchangeRateSD
            )
        );

        fee = _quote(_params.dstEid, payload, options, _payInLzToken);
    }

    function _removeDust(
        uint256 _amountLD,
        address _tokenAddress
    ) private view returns (uint64 amountSD, uint256 amountLD) {
        uint256 decimalConversionRate = _tokenAddress == address(0)
            ? 10 ** 12 // native
            : 10 ** (ERC20(_tokenAddress).decimals() - SHARED_DECIMALS); // token

        (amountSD, amountLD) = AmountCast.removeDust(_amountLD, decimalConversionRate);
    }

    function _buildCreateOfferMsgAndOptions(
        bytes32 _offerId,
        Offer memory _offer
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
        override
        returns (
            bytes32 offerId,
            bytes32 advertiser,
            bytes32 beneficiary,
            uint32 srcEid,
            uint32 dstEid,
            bytes32 srcTokenAddress,
            bytes32 dstTokenAddress,
            uint64 srcAmountSD,
            uint64 exchangeRateSD
        )
    {
        offerId = _payload.toB32(0);
        advertiser = _payload.toB32(32);
        beneficiary = _payload.toB32(64);
        srcEid = _payload.toU32(96);
        dstEid = _payload.toU32(100);
        srcTokenAddress = _payload.toB32(104);
        dstTokenAddress = _payload.toB32(136);
        srcAmountSD = _payload.toU64(168);
        exchangeRateSD = _payload.toU64(176);
    }

    function _receiveCreateOffer(bytes32 _offerId, Offer memory _offer) internal virtual override {
        offers[_offerId] = _offer;

        emit OfferCreated(_offerId, _offer);
    }
}
