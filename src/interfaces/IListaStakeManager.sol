// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ListaStakeManager Contract interface
/// @notice Stakes BNB and get slisBNB
interface IListaStakeManager {
  function deposit() external payable;
}
