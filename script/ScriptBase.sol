// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script } from "forge-std/Script.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { sd1x18 } from "prb-math/SD1x18.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { IPool, IRewardsController, AaveV3ERC4626, ERC20 } from "yield-daddy/aave-v3/AaveV3ERC4626.sol";

import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { TpdaLiquidationPairFactory, TpdaLiquidationPair } from "pt-v5-tpda-liquidator/TpdaLiquidationPairFactory.sol";
import { AaveV3ERC4626LiquidatorFactory, AaveV3ERC4626Liquidator, IPrizePool } from "pt-v5-yield-daddy-liquidators/AaveV3ERC4626LiquidatorFactory.sol";
import { PrizeVaultFactory, PrizeVault, IERC4626 } from "pt-v5-vault/PrizeVaultFactory.sol";

struct Configuration {
    // LP Config
    TpdaLiquidationPairFactory lpFactory;
    uint256 lpTargetAuctionPeriod;
    uint192 lpTargetAuctionPrice;
    uint256 lpSmoothingFactor;

    // Reward LP Config
    AaveV3ERC4626LiquidatorFactory rewardLpFactory;
    uint256 rewardLpTargetAuctionPeriod;
    uint192 rewardLpTargetAuctionPrice;
    uint256 rewardLpSmoothingFactor;

    // Yield Vault Config
    address yieldVaultComputedAddress;
    IPool aaveV3Pool;
    IRewardsController aaveV3RewardsController;
    ERC20 aaveV3Asset;

    // Prize Vault Config
    PrizePool prizePool;
    PrizeVaultFactory prizeVaultFactory;
    address claimer;
    string prizeVaultName;
    string prizeVaultSymbol;
    address prizeVaultOwner;
    address prizeVaultYieldFeeRecipient;
    uint32 prizeVaultYieldFeePercentage;
}

contract ScriptBase is Script {
    using SafeCast for uint256;

    function loadConfig(string memory filepath) internal view returns (Configuration memory config) {
        string memory file = vm.readFile(filepath);

        // LP Config
        config.lpFactory                    = TpdaLiquidationPairFactory(vm.parseJsonAddress(file, "$.lpFactory"));
        config.lpTargetAuctionPeriod        = vm.parseJsonUint(file, "$.lpTargetAuctionPeriod");
        config.lpTargetAuctionPrice         = vm.parseJsonUint(file, "$.lpTargetAuctionPrice").toUint192();
        config.lpSmoothingFactor            = vm.parseJsonUint(file, "$.lpSmoothingFactor");

        // Reward LP Config
        config.rewardLpFactory              = AaveV3ERC4626LiquidatorFactory(vm.parseJsonAddress(file, "$.rewardLpFactory"));
        config.rewardLpTargetAuctionPeriod  = vm.parseJsonUint(file, "$.rewardLpTargetAuctionPeriod");
        config.rewardLpTargetAuctionPrice   = vm.parseJsonUint(file, "$.rewardLpTargetAuctionPrice").toUint192();
        config.rewardLpSmoothingFactor      = vm.parseJsonUint(file, "$.rewardLpSmoothingFactor");

        // Yield Vault Config
        config.yieldVaultComputedAddress    = vm.parseJsonAddress(file, "$.yieldVaultComputedAddress");
        config.aaveV3Pool                   = IPool(vm.parseJsonAddress(file, "$.aaveV3Pool"));
        config.aaveV3RewardsController      = IRewardsController(vm.parseJsonAddress(file, "$.aaveV3RewardsController"));
        config.aaveV3Asset                  = ERC20(vm.parseJsonAddress(file, "$.aaveV3Asset"));

        // Prize Vault
        config.prizePool                    = PrizePool(vm.parseJsonAddress(file, "$.prizePool"));
        config.prizeVaultFactory            = PrizeVaultFactory(vm.parseJsonAddress(file, "$.prizeVaultFactory"));
        config.claimer                      = vm.parseJsonAddress(file, "$.claimer");
        config.prizeVaultName               = vm.parseJsonString(file, "$.prizeVaultName");
        config.prizeVaultSymbol             = vm.parseJsonString(file, "$.prizeVaultSymbol");
        config.prizeVaultOwner              = vm.parseJsonAddress(file, "$.prizeVaultOwner");
        config.prizeVaultYieldFeeRecipient  = vm.parseJsonAddress(file, "$.prizeVaultYieldFeeRecipient");
        config.prizeVaultYieldFeePercentage = vm.parseJsonUint(file, "$.prizeVaultYieldFeePercentage").toUint32();
    }

}