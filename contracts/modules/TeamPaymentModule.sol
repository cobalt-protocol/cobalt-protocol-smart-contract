// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ManagerStorage} from "./ManagerStorage.sol";
import {CompetitionHelper} from "../helpers/CompetitionHelper.sol";

/// @title TeamPaymentModule
/// @notice Escrow biaya tim: paymentCreateTeam, withdrawTeamPayment, claimTeamPayment.
abstract contract TeamPaymentModule is ManagerStorage {
    error NativeFromMismatch();
    error WithdrawTooEarly();

    event TeamPaymentCreated(
        uint256 indexed competitionId,
        string cid,
        address indexed token,
        address indexed from,
        address to,
        uint256 amount,
        bytes signature
    );

    event TeamPaymentWithdrawn(
        uint256 indexed competitionId,
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /**
     * @notice Pembayaran biaya tim untuk sebuah kompetisi.
     * Dana akan disimpan di dalam kontrak (escrow) dan dicatat di totalPaid.
     * Organization bisa menariknya nanti melalui claimTeamPayment / withdrawTeamPayment.
     */
    function paymentCreateTeam(
        uint256 _competitionId,
        string calldata cid,
        bytes calldata _signature
    ) external payable {
        Competitions storage comp = competitions[_competitionId];
        if (comp.id == 0) revert CompetitionDoesNotExist();

        CompetitionHelper.verifySig(
            keccak256(abi.encodePacked(address(this), _competitionId, cid)),
            _signature,
            signerAddress
        );

        if (comp.payment.tokenAddress == address(0)) {
            if (msg.sender != msg.sender) revert NativeFromMismatch();
            if (msg.value != comp.payment.fee) revert IncorrectNativeAmount();
        } else {
            if (msg.value != 0) revert IncorrectNativeAmount();
            if (
                !IERC20(comp.payment.tokenAddress).transferFrom(
                    msg.sender,
                    address(this),
                    comp.payment.fee
                )
            ) revert TransferFailed();
        }

        totalPaid[_competitionId][comp.payment.tokenAddress] += comp
            .payment
            .fee;

        emit TeamPaymentCreated(
            _competitionId,
            cid,
            comp.payment.tokenAddress,
            msg.sender,
            address(this),
            comp.payment.fee,
            _signature
        );
    }

    /**
     * @notice Tarik dana hasil paymentCreateTeam (versi lama).
     * Hanya organization kompetisi yang boleh menarik.
     * Syarat: hadiah BELUM didistribusikan + sudah lewat 7 hari setelah end time + signature.
     */
    function withdrawTeamPayment(
        uint256 _competitionId,
        address _token,
        uint256 _amount,
        string calldata _teamId,
        bytes calldata _signature
    ) external competitionExists(_competitionId) {
        if (_amount == 0) revert AmountZero();
        if (bytes(_teamId).length == 0) revert InvalidTeamId();
        if (totalPaid[_competitionId][_token] < _amount)
            revert InsufficientPrizeBalance();

        if (prizesDistributed[_competitionId]) {
            revert PrizesAlreadyDistributed();
        }

        uint256 competitionEndTime = competitions[_competitionId]
            .prizeCertificateClaim;
        uint256 sevenDays = 7 days;

        if (block.timestamp < competitionEndTime + sevenDays) {
            revert WithdrawTooEarly();
        }

        CompetitionHelper.verifySig(
            keccak256(
                abi.encodePacked(
                    address(this),
                    _competitionId,
                    _token,
                    _amount,
                    _teamId,
                    msg.sender
                )
            ),
            _signature,
            signerAddress
        );

        totalPaid[_competitionId][_token] -= _amount;

        if (_token == address(0)) {
            (bool ok, ) = payable(msg.sender).call{value: _amount}("");
            if (!ok) revert TransferFailed();
        } else {
            if (!IERC20(_token).transfer(msg.sender, _amount))
                revert TransferFailed();
        }

        emit TeamPaymentWithdrawn(_competitionId, _token, msg.sender, _amount);
    }

    /**
     * @notice Claim / tarik dana hasil paymentCreateTeam.
     * Hanya setelah semua hadiah sudah didistribusikan (prizesDistributed = true).
     */
    function claimTeamPayment(
        uint256 _competitionId,
        address _token,
        uint256 _amount
    ) external competitionExists(_competitionId) {
        if (_amount == 0) revert AmountZero();
        if (!prizesDistributed[_competitionId]) revert PrizesNotDistributed();
        if (totalPaid[_competitionId][_token] < _amount)
            revert InsufficientPrizeBalance();

        totalPaid[_competitionId][_token] -= _amount;

        if (_token == address(0)) {
            (bool ok, ) = payable(msg.sender).call{value: _amount}("");
            if (!ok) revert TransferFailed();
        } else {
            if (!IERC20(_token).transfer(msg.sender, _amount))
                revert TransferFailed();
        }

        emit TeamPaymentWithdrawn(_competitionId, _token, msg.sender, _amount);
    }
}
