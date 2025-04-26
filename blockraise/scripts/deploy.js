// const hre = require("hardhat");
// const routerAddresses = {
//     Sepolia: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
//     Fuji: "0xF694E193200268f9a4868e4Aa017A0118C9a8177",
//     Amoy: "0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2",
// }; // Replace with Chainlink CCIP Router Address
// const linkTokenAddresses = {
//     Sepolia: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
//     Fuji: "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846",
//     Amoy: "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904",
// }; // Replace with LINK token address on the chain

// async function main() {
//     const network = hre.network.name; // Get current network
//     const routerAddress = routerAddresses[network];
//     const linkTokenAddress = linkTokenAddresses[network];

//     if (!routerAddress || !linkTokenAddress) {
//         throw new Error(`Router or LINK token address not found for ${network}`);
//     }

//     console.log(`Deploying to ${network} using router ${routerAddress} and LINK ${linkTokenAddress}`);
    
//     // Get the contract factory
//     const CrowdFunding = await hre.ethers.getContractFactory("CrowdFunding");
    
//     // Deploy contract
//     const deployTx = await CrowdFunding.deploy(routerAddress, linkTokenAddress);
    
//     // Your environment seems to directly have the address property on the deployment result
//     console.log(`CrowdFunding deployed on ${network} at:`, deployTx.address);
// }

// main().catch((error) => {
//     console.error(error);
//     process.exitCode = 1;
// });

// const hre = require("hardhat");
// const routerAddresses = {
//     Sepolia: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
//     Fuji: "0xF694E193200268f9a4868e4Aa017A0118C9a8177",
//     Amoy: "0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2",
// }; // Replace with Chainlink CCIP Router Address
// const linkTokenAddresses = {
//     Sepolia: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
//     Fuji: "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846",
//     Amoy: "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904",
// }; // Replace with LINK token address on the chain

// async function main() {
//     const network = hre.network.name; // Get current network
//     const routerAddress = routerAddresses[network];
//     const linkTokenAddress = linkTokenAddresses[network];

//     if (!routerAddress || !linkTokenAddress) {
//         throw new Error(`Router or LINK token address not found for ${network}`);
//     }

//     console.log(`Deploying to ${network} using router ${routerAddress} and LINK ${linkTokenAddress}`);
    
//     // Get the contract factory
//     const CrowdFunding = await hre.ethers.getContractFactory("CrowdFunding");
    
//     // Deploy contract and wait for it to be mined
//     const deployTx = await CrowdFunding.deploy(routerAddress, linkTokenAddress);
//     const deployedContract = await deployTx.deployed();
    
//     console.log(`CrowdFunding deployed on ${network} at:`, deployedContract.address);
// }

// main().catch((error) => {
//     console.error(error);
//     process.exitCode = 1;
// });

const hre = require("hardhat");
const routerAddresses = {
    Sepolia: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
    Fuji: "0xF694E193200268f9a4868e4Aa017A0118C9a8177",
    Amoy: "0x9C32fCB86BF0f4a1A8921a9Fe46de3198bb884B2",
};
const linkTokenAddresses = {
    Sepolia: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
    Fuji: "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846",
    Amoy: "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904",
};

async function main() {
    const network = hre.network.name;
    const routerAddress = routerAddresses[network];
    const linkTokenAddress = linkTokenAddresses[network];

    if (!routerAddress || !linkTokenAddress) {
        throw new Error(`Router or LINK token address not found for ${network}`);
    }

    console.log(`Deploying to ${network} using router ${routerAddress} and LINK ${linkTokenAddress}`);
    
    // Get the contract factory
    const CrowdFunding = await hre.ethers.getContractFactory("CrowdFunding");
    
    // Deploy contract
    const crowdFunding = await CrowdFunding.deploy(routerAddress, linkTokenAddress);
    
    // Wait for the contract to be deployed
    await crowdFunding.waitForDeployment();
    
    // Get the contract address
    const contractAddress = await crowdFunding.getAddress();
    
    console.log(`CrowdFunding deployed on ${network} at:`, contractAddress);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});





