// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minter interface
interface IAsBnbMinter {

  struct TokenMintReq {
    address user; // user who made the request
    uint256 amountIn; // amount of token deposited
  }

  function compoundRewards(uint256 _amountIn) external;
  function mintAsBnb(uint256 amount) external returns (uint256);
  function burnAsBnb(uint256 amountToBurn) external returns (uint256);

  function convertToTokens(uint256 asBNBAmount) external view returns (uint256);
  function convertToAsBnb(uint256 tokenAmount) external view returns (uint256);
}
