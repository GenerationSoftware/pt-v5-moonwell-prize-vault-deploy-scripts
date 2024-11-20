// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/console2.sol";

import { Test } from "forge-std/Test.sol";
import { PrizeVaultAddressBook, ERC20, TpdaLiquidationPair, IComptroller, PrizePool } from "../script/DeployMoonwellPrizeVault.s.sol";
import { MToken } from "moonwell-contracts-v2/MToken.sol";

/// @notice Runs some basic fork tests against a deployment
contract PrizeVaultPostDeployTest is Test {

    uint256 deployFork;
    PrizeVaultAddressBook addressBook;
    address WELL = address(0xA88594D404727625A9437C3f886C7643872296AE);
    uint256 precisionLoss = 1; // default 1

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
        uint8 decimals = addressBook.prizeVault.decimals();
        if (decimals > 9) {
            precisionLoss = (10 ** (decimals - 9)); // addition precision loss on assets with more than 9 decimals
        }
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
        uint256 maxAmount = asset.balanceOf(address(addressBook.mToken));
        assertGt(maxAmount, 1);
        if (amount >= maxAmount) amount = maxAmount / 2;

        // The mToken address should hold lots of the asset, so we can spoof that address as our "dealer"
        vm.startPrank(address(addressBook.mToken));
        asset.transfer(address(this), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(this)), amount);

        // Test deposit and withdraw
        asset.approve(address(addressBook.prizeVault), amount);
        uint256 shares = addressBook.prizeVault.deposit(amount, address(this));
        assertEq(shares, amount); // 1:1

        // Let yield accrue over time
        uint256 totalAssetsBefore = addressBook.prizeVault.totalAssets();
        assertApproxEqAbs(totalAssetsBefore, amount + addressBook.prizeVault.yieldBuffer(), precisionLoss);
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

    function testWellRewards() public {
        // deposit and let rewards accrue
        address asset = addressBook.prizeVault.asset();
        uint256 depositAmount = 10000 * 10 ^ ERC20(asset).decimals();
        deal(asset, address(this), depositAmount);
        ERC20(asset).approve(address(addressBook.prizeVault), depositAmount);
        addressBook.prizeVault.deposit(depositAmount, address(this));

        TpdaLiquidationPair rewardLp = addressBook.rewardLiquidator.liquidationPairs(address(WELL));
        require(address(rewardLp) != address(0), "not initialized");

        uint256 liquid = addressBook.rewardLiquidator.liquidatableBalanceOf(WELL);
        assertEq(liquid, ERC20(WELL).balanceOf(address(addressBook.rewardLiquidator)));
        if (liquid > 0) {
            
            // Check if LP can liquidate
            vm.warp(rewardLp.lastAuctionAt() + rewardLp.targetAuctionPeriod());
            uint256 maxAmountOut = rewardLp.maxAmountOut();
            assertGt(maxAmountOut, 0);
            uint256 exactAmountIn = rewardLp.computeExactAmountIn(maxAmountOut);
            assertApproxEqRel(exactAmountIn, uint256(rewardLp.lastAuctionPrice()), 0.01e18);

            // liquidate
            PrizePool prizePool = addressBook.prizeVault.prizePool();
            ERC20 prizeToken = ERC20(address(prizePool.prizeToken()));
            deal(address(prizeToken), address(this), exactAmountIn);
            prizeToken.approve(address(addressBook.lpRouter), exactAmountIn);
            uint256 amountIn = addressBook.lpRouter.swapExactAmountOut(
                rewardLp,
                address(this),
                maxAmountOut,
                exactAmountIn,
                block.timestamp
            );
            assertEq(amountIn, exactAmountIn);
            assertEq(ERC20(WELL).balanceOf(address(this)), maxAmountOut);
            uint24 openDrawId = prizePool.getOpenDrawId();
            assertEq(prizePool.getContributedBetween(address(addressBook.prizeVault), openDrawId, openDrawId), exactAmountIn);
        }
    }

}