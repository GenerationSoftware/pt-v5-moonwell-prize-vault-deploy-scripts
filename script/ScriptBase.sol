// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { sd1x18 } from "prb-math/SD1x18.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { CompoundERC4626, IComptroller, MErc20, ERC20 } from "moonwell-contracts-v2/4626/CompoundERC4626.sol";

import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { TpdaLiquidationPairFactory, TpdaLiquidationPair } from "pt-v5-tpda-liquidator/TpdaLiquidationPairFactory.sol";
import { TpdaLiquidationRouter } from "pt-v5-tpda-liquidator/TpdaLiquidationRouter.sol";
import { RewardLiquidatorFactory, RewardLiquidator, IPrizePool } from "pt-v5-yield-daddy-liquidators/RewardLiquidatorFactory.sol";
import { IRewardSource } from "pt-v5-yield-daddy-liquidators/external/interfaces/IRewardSource.sol";
import { PrizeVaultFactory, PrizeVault, IERC4626 } from "pt-v5-vault/PrizeVaultFactory.sol";

struct Configuration {
    // LP Config
    TpdaLiquidationPairFactory lpFactory;
    uint64 prizeVaultLpTargetAuctionPeriod;
    uint192 prizeVaultLpTargetAuctionPrice;
    uint256 prizeVaultLpSmoothingFactor;

    // Reward LP Config
    RewardLiquidatorFactory rewardLiquidatorFactory;
    uint64 rewardLpTargetAuctionPeriod;
    uint192 rewardLpTargetAuctionPrice;
    uint256 rewardLpSmoothingFactor;

    // Yield Vault Config
    address yieldVaultComputedAddress;
    IComptroller moonwellComptroller;
    ERC20 moonwellVaultAsset;

    // Prize Vault Config
    PrizePool prizePool;
    PrizeVaultFactory prizeVaultFactory;
    address claimer;
    string prizeVaultName;
    string prizeVaultSymbol;
    address prizeVaultOwner;
    address prizeVaultYieldFeeRecipient;
    uint32 prizeVaultYieldFeePercentage;

    // LP Router
    TpdaLiquidationRouter lpRouter;
}

contract ScriptBase is Script {
    using SafeCast for uint256;

    function loadConfig(string memory filepath) internal view returns (Configuration memory config) {
        string memory file = vm.readFile(filepath);

        // LP Config
        config.lpFactory                                = TpdaLiquidationPairFactory(vm.parseJsonAddress(file, "$.lpFactory"));
        config.prizeVaultLpTargetAuctionPeriod          = vm.parseJsonUint(file, "$.prizeVaultLpTargetAuctionPeriod").toUint64();
        config.prizeVaultLpTargetAuctionPrice           = vm.parseJsonUint(file, "$.prizeVaultLpTargetAuctionPrice").toUint192();
        config.prizeVaultLpSmoothingFactor              = vm.parseJsonUint(file, "$.prizeVaultLpSmoothingFactor");

        // Reward LP Config
        config.rewardLiquidatorFactory                  = RewardLiquidatorFactory(vm.parseJsonAddress(file, "$.rewardLiquidatorFactory"));
        config.rewardLpTargetAuctionPeriod              = vm.parseJsonUint(file, "$.rewardLpTargetAuctionPeriod").toUint64();
        config.rewardLpTargetAuctionPrice               = vm.parseJsonUint(file, "$.rewardLpTargetAuctionPrice").toUint192();
        config.rewardLpSmoothingFactor                  = vm.parseJsonUint(file, "$.rewardLpSmoothingFactor");

        // Yield Vault Config
        config.yieldVaultComputedAddress                = vm.parseJsonAddress(file, "$.yieldVaultComputedAddress");
        config.moonwellComptroller                      = IComptroller(vm.parseJsonAddress(file, "$.moonwellComptroller"));
        config.moonwellVaultAsset                       = ERC20(vm.parseJsonAddress(file, "$.moonwellVaultAsset"));

        // Prize Vault
        config.prizePool                                = PrizePool(vm.parseJsonAddress(file, "$.prizePool"));
        config.prizeVaultFactory                        = PrizeVaultFactory(vm.parseJsonAddress(file, "$.prizeVaultFactory"));
        config.claimer                                  = vm.parseJsonAddress(file, "$.claimer");
        config.prizeVaultName                           = vm.parseJsonString(file, "$.prizeVaultName");
        config.prizeVaultSymbol                         = vm.parseJsonString(file, "$.prizeVaultSymbol");
        config.prizeVaultOwner                          = vm.parseJsonAddress(file, "$.prizeVaultOwner");
        config.prizeVaultYieldFeeRecipient              = vm.parseJsonAddress(file, "$.prizeVaultYieldFeeRecipient");
        config.prizeVaultYieldFeePercentage             = vm.parseJsonUint(file, "$.prizeVaultYieldFeePercentage").toUint32();

        // LP Router
        config.lpRouter                                 = TpdaLiquidationRouter(vm.parseJsonAddress(file, "$.lpRouter"));
    }

}