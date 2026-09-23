// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TreasuryPrize is Ownable {
    struct TreasuryPrize {
        uint256 id;
        uint256 competitionId;
        address organization;
        uint256 totalPrize;
        address tokenAddress;
    }

    uint256 private treasuryPrizeId;

    mapping(uint256 => TreasuryPrize) public treasuryPrize;

    mapping(uint256 => TreasuryPrize) public treasuryPrizeByCompetitionId;

    event PrizeDeposited(
        uint256 indexed treasuryPrizeId,
        uint256 indexed competitionId,
        address indexed tokenAddress,
        address sender,
        uint256 amount
    );

    event PrizeDistributed(
        uint256 indexed treasuryPrizeId,
        uint256 indexed competitionId,
        address indexed tokenAddress,
        address recipient,
        uint256 amount
    );

    event NativeReceived(address indexed sender, uint256 amount);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function addTreasury(
        TreasuryPrize calldata _treasuryPrize,
        address _from
    ) external payable {
        require(_treasuryPrize.totalPrize > 0, "Amount must be greater than 0");

        address sender = _from == address(0) ? msg.sender : _from;

        if (_treasuryPrize.tokenAddress == address(0)) {
            require(
                msg.value == _treasuryPrize.totalPrize,
                "Incorrect native amount"
            );
        } else {
            require(msg.value == 0, "Do not send native token");
            bool success = IERC20(_treasuryPrize.tokenAddress).transferFrom(
                sender,
                address(this),
                _treasuryPrize.totalPrize
            );
            require(success, "Transfer failed");
        }

        treasuryPrizeId++;
        TreasuryPrize memory newEntry = TreasuryPrize({
            id: treasuryPrizeId,
            competitionId: _treasuryPrize.competitionId,
            organization: sender,
            totalPrize: _treasuryPrize.totalPrize,
            tokenAddress: _treasuryPrize.tokenAddress
        });

        treasuryPrize[treasuryPrizeId] = newEntry;
        treasuryPrizeByCompetitionId[_treasuryPrize.competitionId] = newEntry;

        emit PrizeDeposited(
            treasuryPrizeId,
            _treasuryPrize.competitionId,
            _treasuryPrize.tokenAddress,
            sender,
            _treasuryPrize.totalPrize
        );
    }

    function payout(
        uint256 _competitionId,
        address payable _to,
        uint256 _amount,
        address _tokenAddress,
        address _from
    ) external {
        address caller = _from == address(0) ? msg.sender : _from;

        TreasuryPrize storage compPrize = treasuryPrizeByCompetitionId[
            _competitionId
        ];
        require(
            compPrize.organization != address(0),
            "Treasury does not exist"
        );
        require(
            caller == compPrize.organization,
            "Only organization can payout"
        );
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be greater than 0");
        require(compPrize.totalPrize >= _amount, "Insufficient prize balance");
        require(
            compPrize.tokenAddress == _tokenAddress,
            "Token address mismatch"
        );

        compPrize.totalPrize -= _amount;

        uint256 tId = compPrize.id;
        if (tId != 0) {
            treasuryPrize[tId].totalPrize -= _amount;
        }

        if (_tokenAddress == address(0)) {
            (bool success, ) = _to.call{value: _amount}("");
            require(success, "Native transfer failed");
        } else {
            bool success = IERC20(_tokenAddress).transfer(_to, _amount);
            require(success, "Transfer failed");
        }

        emit PrizeDistributed(tId, _competitionId, _tokenAddress, _to, _amount);
    }

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
}
