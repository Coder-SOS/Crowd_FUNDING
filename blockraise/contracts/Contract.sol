// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.9;

// import "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
// import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
// import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";  // ✅ FIXED: Import IERC20

// contract CrowdFunding {
//     struct Campaign {
//         address owner;
//         string title;
//         uint256 target;
//         string imageURL;
//         string description;
//         uint256 receivedAmount;
//         uint256 deadline;
//     }

//     mapping(uint256 => Campaign) private campaigns;
//     uint256 public numberOfCampaigns = 0;

//     IRouterClient public router;
//     address public linkToken;

//     event DonationReceived(uint256 campaignId, address donor, uint256 amount);
//     event FundsWithdrawn(uint256 campaignId, address owner, uint256 amount);
//     event CCIPMessageSent(uint64 indexed destinationChain);

//     modifier onlyOwner(uint256 _id) {
//         require(_id < numberOfCampaigns, "Campaign does not exist");
//         require(msg.sender == campaigns[_id].owner, "Only the campaign owner can perform this action");
//         _;
//     }

//     constructor(address _router, address _linkToken) {
//         router = IRouterClient(_router);
//         linkToken = _linkToken;
//     }

//     function createCampaign(
//         string memory _title,
//         string memory _description,
//         uint256 _target,
//         uint256 _deadline,
//         string memory _imageURL
//     ) public returns (uint256) {
//         require(_target > 0, "Target amount must be greater than zero");
//         require(_deadline > block.timestamp, "Deadline should be in the future");

//         Campaign storage campaign = campaigns[numberOfCampaigns];

//         campaign.owner = msg.sender;
//         campaign.title = _title;
//         campaign.description = _description;
//         campaign.target = _target;
//         campaign.deadline = _deadline;
//         campaign.imageURL = _imageURL;
//         campaign.receivedAmount = 0;

//         unchecked {
//             numberOfCampaigns++;
//         }
//         return numberOfCampaigns - 1;
//     }

//     function donateToCampaign(uint256 _id, uint64 _destinationChainSelector, address _destinationContract) public payable {
//         require(_id < numberOfCampaigns, "Campaign does not exist");

//         Campaign storage campaign = campaigns[_id];

//         require(campaign.receivedAmount + msg.value <= campaign.target, "Donation exceeds funding goal");
//         require(msg.value > 0, "You can't fund zero :(");
//         require(campaign.deadline > block.timestamp, "The campaign has ended");

//         if (block.chainid == _destinationChainSelector) {
//             // Same chain donation, process normally
//             campaign.receivedAmount += msg.value;
//             emit DonationReceived(_id, msg.sender, msg.value);
//         } else {
//             // Cross-chain donation using CCIP
//             bytes memory message = abi.encode(_id, msg.sender, msg.value);

//             Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
//                 receiver: abi.encode(_destinationContract),
//                 data: message,
//                 tokenAmounts: new Client.EVMTokenAmount[](0), // ✅ : Empty array syntax
//                 extraArgs: "",
//                 feeToken: linkToken
//             });

//             uint256 fee = router.getFee(_destinationChainSelector, ccipMessage);
//             require(IERC20(linkToken).balanceOf(msg.sender) >= fee, "Insufficient LINK for CCIP fee");
//             IERC20(linkToken).approve(address(router), fee);

//             router.ccipSend(_destinationChainSelector, ccipMessage);
//             emit CCIPMessageSent(_destinationChainSelector);
//         }
//     }

//     function withdrawFunds(uint256 _id, uint256 _amount) public onlyOwner(_id) {
//         Campaign storage campaign = campaigns[_id];

//         require(block.timestamp >= campaign.deadline, "Cannot withdraw before the deadline");
//         require(_amount > 0 && _amount <= campaign.receivedAmount, "Invalid withdrawal amount");

//         campaign.receivedAmount -= _amount;

//         (bool sent,) = payable(msg.sender).call{value: _amount}("");
//         require(sent, "Failed to withdraw funds");

//         emit FundsWithdrawn(_id, msg.sender, _amount);
//     }

//     function getBalance(uint256 _id) public view returns (uint256) {
//         require(_id < numberOfCampaigns, "Campaign does not exist");
//         return campaigns[_id].receivedAmount;
//     }

//     function getCampaign(uint256 _id) public view returns (
//         address owner,
//         string memory title,
//         string memory description,
//         uint256 target,
//         uint256 deadline,
//         string memory imageURL,
//         uint256 receivedAmount
//     ) {
//         require(_id < numberOfCampaigns, "Campaign does not exist");

//         Campaign storage campaign = campaigns[_id];
//         return (
//             campaign.owner,
//             campaign.title,
//             campaign.description,
//             campaign.target,
//             campaign.deadline,
//             campaign.imageURL,
//             campaign.receivedAmount
//         );
//     }
// }

pragma solidity ^0.8.9;

import "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Implementing CCIPReceiver to handle cross-chain messages
contract CrowdFunding is CCIPReceiver {
    struct Campaign {
        address owner;
        string title;
        uint256 target;
        string imageURL;
        string description;
        uint256 receivedAmount;
        uint256 deadline;
    }

    mapping(uint256 => Campaign) private campaigns;
    uint256 public numberOfCampaigns = 0;

    // Mapping to track donations that came from other chains
    mapping(bytes32 => bool) public processedMessages;

    // CCIP chain selectors - these are the official Chainlink CCIP identifiers
    mapping(string => uint64) public chainSelectors;

    // Store the router address explicitly in our contract
    IRouterClient private immutable i_router;

    event DonationReceived(
        uint256 campaignId,
        address donor,
        uint256 amount,
        uint64 sourceChain
    );
    event FundsWithdrawn(uint256 campaignId, address owner, uint256 amount);
    event CCIPMessageSent(bytes32 messageId, uint64 destinationChainSelector);
    event MessageReceived(bytes32 messageId, uint64 sourceChainSelector);

    modifier onlyOwner(uint256 _id) {
    require(_id < numberOfCampaigns, "Campaign does not exist");
    require(msg.sender == campaigns[_id].owner, "Only the campaign owner can perform this action");
    _;
}


    constructor(address _router, address _linkToken) CCIPReceiver(_router) {
        // Save router address for later use
        i_router = IRouterClient(_router);

        // Initialize the chain selectors with correct CCIP values
        chainSelectors["Sepolia"] = 16015286601757825753; // Ethereum Sepolia testnet
        chainSelectors["Fuji"] = 14767482510784806043; // Avalanche Fuji testnet
        chainSelectors["Amoy"] = 19248808432998546; // BNB Chain Amoy testnet
    }

    function createCampaign(
        string memory _title,
        string memory _description,
        uint256 _target,
        uint256 _deadline,
        string memory _imageURL
    ) public returns (uint256) {
        require(_target > 0, "Target amount must be greater than zero");
        require(
            _deadline > block.timestamp,
            "Deadline should be in the future"
        );

        Campaign storage campaign = campaigns[numberOfCampaigns];

        campaign.owner = msg.sender;
        campaign.title = _title;
        campaign.description = _description;
        campaign.target = _target;
        campaign.deadline = _deadline;
        campaign.imageURL = _imageURL;
        campaign.receivedAmount = 0;

        unchecked {
            numberOfCampaigns++;
        }
        return numberOfCampaigns - 1;
    }

    // Function to donate to a campaign on the same chain
    function donateToCampaign(uint256 _id) public payable {
        require(_id < numberOfCampaigns, "Campaign does not exist");

        Campaign storage campaign = campaigns[_id];

        require(
            campaign.receivedAmount + msg.value <= campaign.target,
            "Donation exceeds funding goal"
        );
        require(msg.value > 0, "You can't fund zero :(");
        require(campaign.deadline > block.timestamp, "The campaign has ended");

        campaign.receivedAmount += msg.value;
        emit DonationReceived(_id, msg.sender, msg.value, 0); // 0 indicates same chain
    }

    // Function to donate across chains using CCIP
    function donateAcrossChains(
        uint256 _id,
        string memory _destinationChain,
        address _destinationContract
    ) public payable {
        require(_id < numberOfCampaigns, "Campaign does not exist");
        require(msg.value > 0, "You can't fund zero :(");

        uint64 destinationChainSelector = chainSelectors[_destinationChain];
        require(
            destinationChainSelector != 0,
            "Destination chain not supported"
        );

        // Prepare the message to be sent across chains
        bytes memory message = abi.encode(_id, msg.sender, msg.value);

        // In the latest CCIP implementation, we create the extraArgs with only the gasLimit
        // The strict parameter is handled separately
        Client.EVMExtraArgsV1 memory extraArgs = Client.EVMExtraArgsV1({
            gasLimit: 200000 // Set an appropriate gas limit
        });

        // Create CCIP message
        Client.EVM2AnyMessage memory ccipMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_destinationContract),
            data: message,
            tokenAmounts: new Client.EVMTokenAmount[](0), // No tokens in this simplified version
            extraArgs: Client._argsToBytes(extraArgs),
            feeToken: address(0) // Use native token for fees
        });

        // Calculate the fee needed
        uint256 fee = i_router.getFee(destinationChainSelector, ccipMessage);
        require(msg.value >= fee, "Insufficient funds for CCIP fee");

        // Send CCIP message with the fee attached
        // Note: In the latest CCIP implementation, the strict parameter might be handled
        // in a different way, potentially as a parameter to ccipSend or a separate setting
        // For now, we'll use the standard ccipSend method
        bytes32 messageId = i_router.ccipSend{value: fee}(
            destinationChainSelector,
            ccipMessage
        );

        // Emit event with the message ID
        emit CCIPMessageSent(messageId, destinationChainSelector);
    }

    // Implementation of _ccipReceive from the CCIPReceiver contract
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // Verify this message hasn't been processed already
        bytes32 messageId = message.messageId;
        require(!processedMessages[messageId], "Message already processed");
        processedMessages[messageId] = true;

        // Decode the message data
        (uint256 campaignId, address donor, uint256 amount) = abi.decode(
            message.data,
            (uint256, address, uint256)
        );

        // Ensure the campaign exists
        require(campaignId < numberOfCampaigns, "Campaign does not exist");
        Campaign storage campaign = campaigns[campaignId];

        // Ensure donation doesn't exceed target
        require(
            campaign.receivedAmount + amount <= campaign.target,
            "Donation exceeds funding goal"
        );
        require(campaign.deadline > block.timestamp, "The campaign has ended");

        // Update the campaign with the donation
        campaign.receivedAmount += amount;

        // Emit event
        emit DonationReceived(
            campaignId,
            donor,
            amount,
            message.sourceChainSelector
        );
        emit MessageReceived(messageId, message.sourceChainSelector);
    }

    function withdrawFunds(uint256 _id, uint256 _amount) public onlyOwner(_id) {
        Campaign storage campaign = campaigns[_id];

        require(
            block.timestamp >= campaign.deadline,
            "Cannot withdraw before the deadline"
        );
        require(
            _amount > 0 && _amount <= campaign.receivedAmount,
            "Invalid withdrawal amount"
        );

        campaign.receivedAmount -= _amount;

        (bool sent, ) = payable(msg.sender).call{value: _amount}("");
        require(sent, "Failed to withdraw funds");

        emit FundsWithdrawn(_id, msg.sender, _amount);
    }

    function getBalance(uint256 _id) public view returns (uint256) {
        require(_id < numberOfCampaigns, "Campaign does not exist");
        return campaigns[_id].receivedAmount;
    }

    function getCampaign(
        uint256 _id
    )
        public
        view
        returns (
            address owner,
            string memory title,
            string memory description,
            uint256 target,
            uint256 deadline,
            string memory imageURL,
            uint256 receivedAmount
        )
    {
        require(_id < numberOfCampaigns, "Campaign does not exist");

        Campaign storage campaign = campaigns[_id];
        return (
            campaign.owner,
            campaign.title,
            campaign.description,
            campaign.target,
            campaign.deadline,
            campaign.imageURL,
            campaign.receivedAmount
        );
    }

    // To receive ETH / AVAX directly
    receive() external payable {}

}