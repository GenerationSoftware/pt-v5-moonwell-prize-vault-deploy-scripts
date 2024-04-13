// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/console2.sol";

import { ScriptBase } from "./ScriptBase.sol";

import { AaveV3ERC4626LiquidatorFactory } from "pt-v5-yield-daddy-liquidators/AaveV3ERC4626LiquidatorFactory.sol";

contract DeployRewardLiquidatorFactory is ScriptBase {

    function run() public virtual {
        vm.startBroadcast();

        console2.log("Deploying Aave V3 ERC4626 Reward Liquidator Factory...");
        AaveV3ERC4626LiquidatorFactory factory = new AaveV3ERC4626LiquidatorFactory();
        console2.log("Deployed Address: ", address(factory));

        vm.stopBroadcast();
    }

}
