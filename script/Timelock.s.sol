// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { Timelock } from "../src/Timelock.sol";

contract TimelockScript is Script {
  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {}

  function run() public {
    uint256 deployerPK = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    address[] memory proposers = new address[](1);
    proposers[0] = deployer;
    address[] memory executors = new address[](1);
    executors[0] = deployer;

    vm.startBroadcast(deployerPK);
    Timelock timelock = new Timelock(1 days, 30 days, proposers, executors);
    vm.stopBroadcast();
    console.log("Timelock address: %s", address(timelock));
  }
}
