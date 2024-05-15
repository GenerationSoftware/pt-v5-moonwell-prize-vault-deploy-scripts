// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console2.sol";

import {
    ScriptBase,
    Configuration,
    PrizeVault,
    ERC20,
    IPrizePool,
    PrizePool,
    CompoundERC4626,
    RewardLiquidator,
    IRewardSource,
    TpdaLiquidationPair,
    TpdaLiquidationRouter,
    IERC4626,
    IComptroller,
    MErc20
} from "./ScriptBase.sol";

import { MToken } from "moonwell-contracts-v2/MToken.sol";

import { TwabDelegator, IERC20 } from "pt-v5-twab-delegator/TwabDelegator.sol";

struct PrizeVaultAddressBook {
    PrizeVault prizeVault;
    CompoundERC4626 yieldVault;
    RewardLiquidator rewardLiquidator;
    ERC20 mToken;
    TpdaLiquidationRouter lpRouter;
}

string constant configPath = "config/deploy.json";
string constant addressBookPath = "config/addressBook.txt";

address constant wellAddress = address(0xA88594D404727625A9437C3f886C7643872296AE);
address constant usdcAddress = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

contract DeployPrizeVault is ScriptBase {

    Configuration internal config;
    address internal mTokenAddress;
    address internal prizeVaultComputedAddress;
    uint256 yieldBuffer;

    constructor() {
        config = loadConfig(configPath);
    }

    function run() public virtual {

        // determine a safe yield buffer (moonwell has precision loss on assets with more than 9 decimals)
        uint8 decimals = config.moonwellVaultAsset.decimals();
        yieldBuffer = 1e5;
        if (decimals > 9) {
            yieldBuffer = yieldBuffer * (10 ** (decimals - 9)); // multiply by additional precision loss
        }

        // Pre-deploy checks
        preDeployChecks();

        // Fake deploy a prize vault to see what the address will be
        {
            uint256 snapshot = vm.snapshot();
            
            vm.startPrank(msg.sender);
            config.moonwellVaultAsset.approve(address(config.prizeVaultFactory), yieldBuffer);
            vm.mockCall(config.yieldVaultComputedAddress, abi.encodeWithSignature("asset()"), abi.encode(address(config.moonwellVaultAsset)));
            vm.mockCall(config.yieldVaultComputedAddress, abi.encodeWithSignature("decimals()"), abi.encode(18));
            prizeVaultComputedAddress = address(config.prizeVaultFactory.deployVault(
                config.prizeVaultName,
                config.prizeVaultSymbol,
                IERC4626(config.yieldVaultComputedAddress),
                config.prizePool,
                config.claimer,
                config.prizeVaultYieldFeeRecipient,
                config.prizeVaultYieldFeePercentage,
                yieldBuffer,
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
        RewardLiquidator rewardLiquidator = config.rewardLiquidatorFactory.createLiquidator(
            msg.sender,
            prizeVaultComputedAddress,
            IPrizePool(address(config.prizePool)),
            config.lpFactory,
            config.rewardLpTargetAuctionPeriod,
            config.rewardLpTargetAuctionPrice,
            config.rewardLpSmoothingFactor
        );

        // Find mToken address
        MToken[] memory mTokens = config.moonwellComptroller.getAllMarkets();
        for (uint i = 0; i < mTokens.length; i++) {
            if (MErc20(address(mTokens[i])).underlying() == address(config.moonwellVaultAsset)) {
                mTokenAddress = address(mTokens[i]);
            }
        }
        require(mTokenAddress != address(0), "Failed to find mToken for asset. Does the market exist?");

        // Deploy Moonwell yield vault
        CompoundERC4626 yieldVault = new CompoundERC4626(
            config.moonwellVaultAsset,
            MErc20(mTokenAddress),
            address(rewardLiquidator),
            config.moonwellComptroller
        );
        if (address(yieldVault) != config.yieldVaultComputedAddress) {
            revert("Yield vault address does not match the pre computed address!");
        }

        // Deploy prize vault
        config.moonwellVaultAsset.approve(address(config.prizeVaultFactory), yieldBuffer);
        PrizeVault prizeVault = config.prizeVaultFactory.deployVault(
            config.prizeVaultName,
            config.prizeVaultSymbol,
            IERC4626(config.yieldVaultComputedAddress),
            config.prizePool,
            config.claimer,
            config.prizeVaultYieldFeeRecipient,
            config.prizeVaultYieldFeePercentage,
            yieldBuffer,
            msg.sender
        );
        if (address(prizeVault) != prizeVaultComputedAddress) {
            revert("Prize vault address does not match pre-computed address!");
        }

        // Initialize reward liquidator
        rewardLiquidator.setYieldVault(IRewardSource(address(yieldVault)));

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

        // Initialize active rewards
        rewardLiquidator.initializeRewardToken(wellAddress);
        if (address(config.moonwellVaultAsset) == usdcAddress) {
            rewardLiquidator.initializeRewardToken(usdcAddress);
        }

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
                        mToken: ERC20(mTokenAddress),
                        lpRouter: config.lpRouter
                    })
                )
            )
        );
    }

    function preDeployChecks() internal virtual {
        // Check asset balance is enough for yield buffer
        if (config.moonwellVaultAsset.balanceOf(msg.sender) < yieldBuffer) {
            console2.log("The deployer address must have a small amount of the deposit asset to donate to the prize vault.");
            console2.log("Amount needed: ", yieldBuffer);
            revert("Missing yield buffer asset balance...");
        }
    }

}
