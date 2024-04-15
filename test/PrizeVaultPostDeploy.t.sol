// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/console2.sol";

import { Test } from "forge-std/Test.sol";
import { PrizeVaultAddressBook, ERC20, TpdaLiquidationPair, IRewardsController } from "../script/DeployAaveV3PrizeVault.s.sol";

/// @notice Runs some basic fork tests against a deployment
contract PrizeVaultPostDeployTest is Test {

    uint256 deployFork;
    PrizeVaultAddressBook addressBook;

    constructor() {
        deployFork = vm.createFork(vm.envString("SCRIPT_RPC_URL"));
        addressBook = abi.decode(
            vm.parseBytes(
                vm.readFile(
                    string.concat("config/addressBook.txt")
                )
            ),
            (PrizeVaultAddressBook)
        );
    }
    
    function setUp() public {
        vm.selectFork(deployFork);
    }

    function testAddressBook() public view {
        assertNotEq(address(0), address(addressBook.prizeVault));
        assertNotEq(address(0), address(addressBook.yieldVault));
        assertNotEq(address(0), address(addressBook.rewardLiquidator));
    }

    function testContractConnections() public view {
        assertEq(address(addressBook.prizeVault.yieldVault()), address(addressBook.yieldVault));
        assertEq(addressBook.yieldVault.rewardRecipient(), address(addressBook.rewardLiquidator));
        assertEq(addressBook.rewardLiquidator.vaultBeneficiary(), address(addressBook.prizeVault));
    }

    function testDepositAndWithdrawWithYield() public {
        ERC20 asset = ERC20(addressBook.prizeVault.asset());
        uint256 amount = 10 ** asset.decimals();
        uint256 maxAmount = asset.balanceOf(address(addressBook.aToken));
        assertGt(maxAmount, 1);
        if (amount >= maxAmount) amount = maxAmount / 2;

        // The aToken address should hold lots of the asset, so we can spoof that address as our "dealer"
        vm.startPrank(address(addressBook.aToken));
        asset.transfer(address(this), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(this)), amount);

        // Test deposit and withdraw
        asset.approve(address(addressBook.prizeVault), amount);
        uint256 shares = addressBook.prizeVault.deposit(amount, address(this));
        assertEq(shares, amount); // 1:1

        // Let yield accrue over time
        uint256 totalAssetsBefore = addressBook.prizeVault.totalAssets();
        assertApproxEqAbs(totalAssetsBefore, amount + addressBook.prizeVault.yieldBuffer(), 1);
        vm.warp(block.timestamp + 10 days);
        uint256 totalAssetsAfter = addressBook.prizeVault.totalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore);

        // Withdraw full amount
        assertEq(addressBook.prizeVault.balanceOf(address(this)), amount);
        uint256 assets = addressBook.prizeVault.redeem(amount, address(this), address(this));
        assertEq(assets, amount);

        // Test that yield still exists in prize vault
        assertGt(addressBook.prizeVault.totalAssets(), totalAssetsBefore - amount);
        assertGt(addressBook.prizeVault.liquidatableBalanceOf(address(addressBook.prizeVault)), 0);
    }

    function testAaveRewardLp() public {
        // spoof `asset` rewards to the yield vault and test that the LP picks them up
        ERC20 asset = ERC20(addressBook.prizeVault.asset());
        uint256 amount = 10 ** asset.decimals();
        uint256 maxAmount = asset.balanceOf(address(addressBook.aToken));
        assertGt(maxAmount, 1);
        if (amount >= maxAmount) amount = maxAmount / 2;

        // The aToken address should hold lots of the asset, so we can spoof that address as our "dealer"
        vm.startPrank(address(addressBook.aToken));
        asset.transfer(address(addressBook.rewardLiquidator), amount);
        vm.stopPrank();

        // Create new reward LP
        TpdaLiquidationPair aaveRewardLp = addressBook.rewardLiquidator.initializeRewardToken(address(asset));

        // Check if rewards are picked up
        address[] memory rewardsList = new address[](1);
        rewardsList[0] = address(asset);
        uint256[] memory claimedAmounts = new uint256[](1);
        claimedAmounts[0] = amount;
        vm.mockCall(
            address(addressBook.yieldVault.rewardsController()),
            abi.encodeWithSelector(IRewardsController.claimAllRewards.selector),
            abi.encode(rewardsList, claimedAmounts)
        );
        uint256 liquid = addressBook.rewardLiquidator.liquidatableBalanceOf(address(asset));
        assertEq(liquid, amount);

        // Check if LP can liquidate
        vm.warp(block.timestamp + aaveRewardLp.targetAuctionPeriod());
        uint256 maxAmountOut = aaveRewardLp.maxAmountOut();
        assertGt(maxAmountOut, 0);
        assertLe(maxAmountOut, amount);
        assertApproxEqAbs(aaveRewardLp.computeExactAmountIn(maxAmountOut), uint256(aaveRewardLp.lastAuctionPrice()), 1);
    }

}