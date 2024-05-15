const readline = require('node:readline');
const fs = require('fs/promises');
const { exec } = require('node:child_process');

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const main = async () => {

    const asciiHeader = await fs.readFile("./config/ascii.txt", "utf8");

    // Display Script Header:
    console.log(asciiHeader);
    console.log("______     _           _   _             _ _    ______           _                       ");
    console.log("| ___ \\   (_)         | | | |           | | |   |  _  \\         | |                      ");
    console.log("| |_/ / __ _ _______  | | | | __ _ _   _| | |_  | | | |___ _ __ | | ___  _   _  ___ _ __ ");
    console.log("|  __/ '__| |_  / _ \\ | | | |/ _` | | | | | __| | | | / _ \\ '_ \\| |/ _ \\| | | |/ _ \\ '__|");
    console.log("| |  | |  | |/ /  __/ \\ \\_/ / (_| | |_| | | |_  | |/ /  __/ |_) | | (_) | |_| |  __/ |   ");
    console.log("\\_|  |_|  |_/___\\___|  \\___/ \\__,_|\\__,_|_|\\__| |___/ \\___| .__/|_|\\___/ \\__, |\\___|_|   ");
    console.log("                                                          | |             __/ |          ");
    console.log("                                                          |_|            |___/           ");
    console.log("");
    console.log("-----------------------------------------------------------------------------------------");
    console.log("| Author: G9 Software Inc.                                                              |");
    console.log("| License: MIT                                                                          |");
    console.log("-----------------------------------------------------------------------------------------\n");

    // Load starting params:
    console.log(`Loading chain params from ${process.env.CONFIG}...`);
    const params = JSON.parse(await fs.readFile(process.env.CONFIG, 'utf-8'));
    console.log("Chain params loaded!\n");

    // Ask for missing param inputs:
    // Asset
    while (!params.moonwellVaultAsset) {
        const input = await ask("Enter the address of the Moonwell asset (the erc20 token being deposited): ");
        if (isAddress(input)) {
            params.moonwellVaultAsset = input;
        } else {
            console.warn("Invalid address...");
        }
    }
    console.log("");

    // Name
    while (!params.prizeVaultName) {
        params.prizeVaultName = await ask("Enter the name of the new prize vault (ex. Prize USDC): ");
    }
    console.log("");

    // Symbol
    while (!params.prizeVaultSymbol) {
        params.prizeVaultSymbol = await ask("Enter the symbol of the new prize vault (ex. przUSDC): ");
    }
    console.log("");

    // Owner
    while (!params.prizeVaultOwner) {
        const input = await ask("Enter the address of the prize vault owner (the owner is able to manage yield and claims on the vault): ");
        if (isAddress(input)) {
            if (input === ZERO_ADDRESS) {
                console.warn("Owner cannot be the zero address (ownership can be renounced later).");
            } else {
                params.prizeVaultOwner = input;
            }
        } else {
            console.warn("Invalid address...");
        }
    }
    console.log("");

    // Yield Fee %
    while (!params.prizeVaultYieldFeePercentage) {
        const input = await ask("Enter the yield fee percentage (ex. 50.2%) (leave blank for 0%): ");
        if (!input) {
            params.prizeVaultYieldFeePercentage = "0";
        } else {
            try {
                const percent = parseFloat(input);
                if (percent > 100) {
                    console.warn("Percent cannot be more than 100%");
                } else {
                    const percent9Decimals = Math.floor(percent * 1e7);
                    params.prizeVaultYieldFeePercentage = "" + percent9Decimals;
                    console.info(`[info] Converted floating point % to 9 decimal fraction: ${params.prizeVaultYieldFeePercentage}`);
                }
            } catch(err) {
                console.warn("Failed to parse float from input. Try again...");
            }
        }
    }
    console.log("");

    // Yield Fee Recipient
    while (!params.prizeVaultYieldFeeRecipient) {
        if (params.prizeVaultYieldFeePercentage === "0") {
            params.prizeVaultYieldFeeRecipient = ZERO_ADDRESS;
        } else {
            const input = await ask("Enter the yield fee recipient address: ");
            if (isAddress(input)) {
                params.prizeVaultYieldFeeRecipient = input;
            } else {
                console.warn("Invalid address...");
            }
        }
    }
    console.log("");

    // Calculate yield vault deployment address:
    console.log("Pre-calculating the yield vault deployment address...");
    const nonce = parseInt(await cast(`nonce ${process.env.SCRIPT_SENDER}`));
    console.log(`Sender nonce is: ${nonce}`);
    params.yieldVaultComputedAddress = "0x" + (await cast(`compute-address ${process.env.SCRIPT_SENDER} --nonce ${nonce + 1} `)).trim().split("0x")[1]; // add 1 to nonce since 1 tx will be sent before deployment
    console.log(`Yield vault address will be: ${params.yieldVaultComputedAddress}\n`);

    // Warn about the yield buffer donation:
    await ask(
        "[WARNING] To deploy a prize vault, a small donation of assets must be made on deployment to fill the yield buffer (1e5 assets). " +
        "For example, if you are deploying a prize vault with USDC, the donation would be worth 1e5 USDC ($0.10). " +
        "These funds must be held by the signing address at the time of deployment and cannot be recovered. " + 
        "Press enter to acknowledge and continue: "
    );

    // Write params to temp config:
    console.log("\nDeploying with the following params: ");
    console.log(params);
    await fs.writeFile("config/deploy.json", JSON.stringify({...params, prizeVaultComputedAddress: "placeholder"}, null, "    "));

    // Double check that they want to deploy:
    const deployResponse = await ask("Would you like to deploy an Moonwell prize vault with these params? (y/n) ");
    rl.close();
    if (deployResponse.toLowerCase().charAt(0) != 'y') {
        console.log("Deployment aborted.");
        process.exit(1);
    }

    process.exit(0);
};

const cast = async (command) => {
    return new Promise((resolve, reject) => {
        exec(`cast ${command} -r ${process.env.SCRIPT_RPC_URL}`, (err, stdout, stderr) => {
            if (err || stderr) {
                reject(err || stderr);
            } else {
                resolve(stdout);
            }
        });
    });
};

const isAddress = (str) => {
    try {
        BigInt(str);
        if (!str.startsWith('0x') || str.length != 42) {
            throw new Error("bad address");
        }
        return true;
    } catch (err) {
        return false;
    }
}

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
});

const ask = async (question) => {
    return new Promise((resolve, reject) => {
        try {
            rl.question(question, result => {
                resolve(result.trim());
            });
        } catch (err) {
            reject(err);
        }
    });
};

main();