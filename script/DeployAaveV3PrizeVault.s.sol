// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/console2.sol";

import {
    ScriptBase,
    Configuration,
    PrizeVault,
    ERC20,
    IPool,
    IPrizePool,
    PrizePool,
    AaveV3ERC4626,
    AaveV3ERC4626Liquidator,
    TpdaLiquidationPair,
    TpdaLiquidationRouter,
    IERC4626,
    IRewardsController
} from "./ScriptBase.sol";

import { TwabDelegator, IERC20 } from "pt-v5-twab-delegator/TwabDelegator.sol";

struct PrizeVaultAddressBook {
    PrizeVault prizeVault;
    AaveV3ERC4626 yieldVault;
    AaveV3ERC4626Liquidator rewardLiquidator;
    ERC20 aToken;
    TpdaLiquidationRouter lpRouter;
}

string constant configPath = "config/deploy.json";
string constant addressBookPath = "config/addressBook.txt";

contract DeployPrizeVault is ScriptBase {

    Configuration internal config;
    address internal aTokenAddress;
    address internal prizeVaultComputedAddress;

    constructor() {
        config = loadConfig(configPath);
    }

    function run() public virtual {

        // Pre-deploy checks
        preDeployChecks();

        // Fake deploy a prize vault to see what the address will be
        {
            uint256 snapshot = vm.snapshot();
            
            vm.startPrank(msg.sender);
            config.aaveV3Asset.approve(address(config.prizeVaultFactory), config.prizeVaultFactory.YIELD_BUFFER());
            vm.mockCall(config.yieldVaultComputedAddress, abi.encodeWithSignature("asset()"), abi.encode(address(config.aaveV3Asset)));
            vm.mockCall(config.yieldVaultComputedAddress, abi.encodeWithSignature("decimals()"), abi.encode(18));
            prizeVaultComputedAddress = address(config.prizeVaultFactory.deployVault(
                config.prizeVaultName,
                config.prizeVaultSymbol,
                IERC4626(config.yieldVaultComputedAddress),
                config.prizePool,
                config.claimer,
                config.prizeVaultYieldFeeRecipient,
                config.prizeVaultYieldFeePercentage,
                msg.sender
            ));
            vm.stopPrank();

            // Store prize vault address in deploy json and then revert to old state
            vm.writeJson(vm.toString(prizeVaultComputedAddress), configPath, ".prizeVaultComputedAddress");
            vm.revertTo(snapshot);

            // Read stored address back into contract
            prizeVaultComputedAddress = vm.parseJsonAddress(vm.readFile(configPath), "$.prizeVaultComputedAddress");
        }

        // Start broadcast
        vm.startBroadcast();

        // Deploy reward liquidator
        AaveV3ERC4626Liquidator rewardLiquidator = config.aaveRewardLiquidatorFactory.createLiquidator(
            msg.sender,
            prizeVaultComputedAddress,
            IPrizePool(address(config.prizePool)),
            config.lpFactory,
            config.aaveRewardLpTargetAuctionPeriod,
            config.aaveRewardLpTargetAuctionPrice,
            config.aaveRewardLpSmoothingFactor
        );

        // Deploy Aave yield vault
        AaveV3ERC4626 yieldVault = new AaveV3ERC4626(
            config.aaveV3Asset,
            ERC20(aTokenAddress),
            config.aaveV3Pool,
            address(rewardLiquidator),
            config.aaveV3RewardsController
        );
        if (address(yieldVault) != config.yieldVaultComputedAddress) {
            revert("Yield vault address does not match the pre computed address!");
        }

        // Deploy prize vault
        config.aaveV3Asset.approve(address(config.prizeVaultFactory), config.prizeVaultFactory.YIELD_BUFFER());
        PrizeVault prizeVault = config.prizeVaultFactory.deployVault(
            config.prizeVaultName,
            config.prizeVaultSymbol,
            IERC4626(config.yieldVaultComputedAddress),
            config.prizePool,
            config.claimer,
            config.prizeVaultYieldFeeRecipient,
            config.prizeVaultYieldFeePercentage,
            msg.sender
        );
        if (address(prizeVault) != prizeVaultComputedAddress) {
            revert("Prize vault address does not match pre-computed address!");
        }

        // Initialize reward liquidator
        rewardLiquidator.setYieldVault(yieldVault);

        // Deploy prize vault LP
        TpdaLiquidationPair lp = config.lpFactory.createPair(
            prizeVault,
            address(config.prizePool.prizeToken()),
            address(prizeVault),
            config.prizeVaultLpTargetAuctionPeriod,
            config.prizeVaultLpTargetAuctionPrice,
            config.prizeVaultLpSmoothingFactor
        );

        // Initialize prize vault
        prizeVault.setLiquidationPair(address(lp));
        if (config.prizeVaultOwner != prizeVault.owner()) {
            prizeVault.transferOwnership(config.prizeVaultOwner);
            console2.log("!!! Prize vault ownership offered! Accept ownership with the prize vault owner address to complete the transfer. !!!");
        }

        // Deploy Twab Delegator for the prize vault
        new TwabDelegator(
            string.concat("Staked ", prizeVault.name()),
            string.concat("st", prizeVault.symbol()),
            prizeVault.twabController(),
            IERC20(address(prizeVault))
        );

        vm.stopBroadcast();

        // dump some addresses for the fork tests to use
        vm.writeFile(
            addressBookPath,
            vm.toString(
                abi.encode(
                    PrizeVaultAddressBook({
                        prizeVault: prizeVault,
                        yieldVault: yieldVault,
                        rewardLiquidator: rewardLiquidator,
                        aToken: ERC20(aTokenAddress),
                        lpRouter: config.lpRouter
                    })
                )
            )
        );
    }

    function preDeployChecks() internal virtual {
        // Check if asset has an aToken
        IPool.ReserveData memory reserveData = config.aaveV3Pool.getReserveData(address(config.aaveV3Asset));
        aTokenAddress = reserveData.aTokenAddress;
        if (aTokenAddress == address(0)) {
            revert("No aToken found for underlying asset in the AaveV3 Pool.");
        }

        // Check asset balance is enough for yield buffer
        if (config.aaveV3Asset.balanceOf(msg.sender) < config.prizeVaultFactory.YIELD_BUFFER()) {
            console2.log("The deployer address must have a small amount of the deposit asset to donate to the prize vault.");
            console2.log("Amount needed: ", config.prizeVaultFactory.YIELD_BUFFER());
            revert("Missing yield buffer asset balance...");
        }
    }

}
