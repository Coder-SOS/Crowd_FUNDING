// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract Crowdfunding is CCIPReceiver {
    // Variables
    address immutable owner;
    string title;
    string description;
    uint256 goal;
    uint256 deadline;
    string imageURL;
    uint256 receivedAmount;
    uint256 withdrawnAmount;
    bool public paused;
    bool private locked; // Reentrancy protection
    IRouterClient private immutable i_router; // Chainlink Router

    struct Backer {
        uint256 totalContribution;
    }

    struct CrossChainDonation {
        address donor;
        uint256 amount;
        uint256 timestamp;
        bool completed;
    }

    // mappings
    mapping(address => Backer) public backers;
    mapping(bytes32 => CrossChainDonation) private pendingCrossChainDonations; // Track pending cross-chain donations

    // Fixed chain selectors
    uint64 private constant SEPOLIA_SELECTOR = 16015286601757825753;
    uint64 private constant FUJI_SELECTOR = 14767482510784806043;
    uint64 private constant AMOY_SELECTOR = 16281711391670634445;

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }
    
    modifier notPaused() {
        require(!paused, "Contract is paused.");
        _;
    }
    
    modifier noReentrant() {
        require(!locked, "Reentrant call detected");
        locked = true;
        _;
        locked = false;
    }

    // events
    event DonationReceived(
        address indexed donor,
        uint256 amount,
        bool isCrossChain
    );
    event FundsWithdrawn(address indexed owner, uint256 amount, bool isEarlyWithdrawal, bool isPartial);
    event DeadlineExtended(uint256 newDeadline);
    event CampaignPaused(bool paused);
    event CrossChainDonationInitiated(bytes32 messageId, address donor, uint256 amount, uint256 gasLimit);
    event UnintendedTransferReceived(address sender, uint256 amount);
    event DonationRefunded(bytes32 indexed messageId, address indexed donor, uint256 amount);
    event MessageCompleted(bytes32 indexed messageId);
    event GoalReached(uint256 timestamp, uint256 finalAmount);

    // Constructor
    constructor(
        address _owner,
        string memory _title,
        string memory _description,
        uint256 _goal,
        uint256 _durationInDays,
        string memory _imgURL,
        address _router //ccip router
    ) CCIPReceiver(_router) {
        require(_owner != address(0), "Invalid owner address");
        require(_goal > 0, "Goal must be greater than 0");
        require(_durationInDays > 0, "Duration must be greater than 0");
        
        owner = _owner;
        title = _title;
        description = _description;
        goal = _goal;
        deadline = block.timestamp + (_durationInDays * 1 days);
        imageURL = _imgURL;
        i_router = IRouterClient(_router);
    }

    // Fund a campaign (native currency)
    function fund() public payable notPaused {
        require(msg.value >= 0.001 ether, "Minimum donation amount required");
        require(
            block.timestamp < deadline,
            "The crowdfunding campaign has ended."
        );

        uint256 previousAmount = receivedAmount;
        receivedAmount += msg.value;
        backers[msg.sender].totalContribution += msg.value;

        emit DonationReceived(msg.sender, msg.value, false); // same chain donation
        
        // Check if goal has been reached with this donation
        if (previousAmount < goal && receivedAmount >= goal) {
            emit GoalReached(block.timestamp, receivedAmount);
        }
    }

    // Receive function to accept direct ETH transfers
    receive() external payable {
        require(msg.value >= 0.001 ether, "Minimum donation amount required");
        fund();
    }

    // Fallback function to handle unintended transfers
    fallback() external payable {
        emit UnintendedTransferReceived(msg.sender, msg.value);
    }

    //cross-chain donations
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        require(!paused, "Contract is paused");
        
        // Verify source chain
        uint64 sourceChainSelector = message.sourceChainSelector;
        require(
            sourceChainSelector == SEPOLIA_SELECTOR ||
            sourceChainSelector == FUJI_SELECTOR ||
            sourceChainSelector == AMOY_SELECTOR,
            "Invalid source chain"
        );
        
        // Decode the received message to extract donor address and donation amount
        (address donor, uint256 amount) = abi.decode(
            message.data,
            (address, uint256)
        );

        require(amount > 0, "Invalid donation amount");
        require(
            block.timestamp < deadline,
            "The crowdfunding campaign has ended."
        );

        uint256 previousAmount = receivedAmount;
        receivedAmount += amount;
        backers[donor].totalContribution += amount;

        // Mark the message as completed
        bytes32 messageId = message.messageId;
        pendingCrossChainDonations[messageId].completed = true;
        
        emit MessageCompleted(messageId);
        emit DonationReceived(donor, amount, true); // cross chain donation
        
        // Check if goal has been reached with this donation
        if (previousAmount < goal && receivedAmount >= goal) {
            emit GoalReached(block.timestamp, receivedAmount);
        }
    }

    // Send to cross chain with exact fee calculation and customizable gas limit
    function sendCrossChainDonation(
        string memory destinationChain,
        uint256 amount,
        uint256 gasLimit
    ) public payable notPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(block.timestamp < deadline, "Campaign has ended");
        require(gasLimit >= 200000, "Gas limit too low"); // Set a minimum to ensure execution
        
        uint64 chainSelector;
        
        // Use fixed chain selectors instead of dynamic mapping
        if (keccak256(bytes(destinationChain)) == keccak256(bytes("Sepolia"))) {
            chainSelector = SEPOLIA_SELECTOR;
        } else if (keccak256(bytes(destinationChain)) == keccak256(bytes("Fuji"))) {
            chainSelector = FUJI_SELECTOR;
        } else if (keccak256(bytes(destinationChain)) == keccak256(bytes("Amoy"))) {
            chainSelector = AMOY_SELECTOR;
        } else {
            revert("Unsupported chain");
        }

        // Set a user-defined gas limit for the destination chain execution
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: abi.encode(msg.sender, amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: gasLimit})),
            feeToken: address(0)
        });

        // Calculate exact fee
        uint256 fee = i_router.getFee(chainSelector, message);
        
        // Require exact amount + fee
        require(msg.value == amount + fee, "Must send exact amount + fee");

        // Send the CCIP message with the fee
        bytes32 messageId = i_router.ccipSend{value: fee}(chainSelector, message);
        
        // Store donation details for potential refund
        pendingCrossChainDonations[messageId] = CrossChainDonation({
            donor: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            completed: false
        });
        
        emit CrossChainDonationInitiated(messageId, msg.sender, amount, gasLimit);
    }

    // Add refund functionality for failed transactions (after timeout)
    function refundFailedDonation(bytes32 messageId) external {
        CrossChainDonation memory donation = pendingCrossChainDonations[messageId];
        
        // Check if donation exists and hasn't been completed
        require(donation.donor != address(0), "Donation not found");
        require(!donation.completed, "Donation already completed");
        
        // Add a reasonable timeout (e.g., 24 hours)
        require(block.timestamp > donation.timestamp + 1 days, "Too early for refund");
        
        // Mark as completed to prevent double refunds
        pendingCrossChainDonations[messageId].completed = true;
        
        // Refund the donor
        (bool sent, ) = payable(donation.donor).call{value: donation.amount}("");
        require(sent, "Failed to refund");
        
        emit DonationRefunded(messageId, donation.donor, donation.amount);
    }

    // Early withdrawal if goal is met before deadline
    function earlyWithdrawal() public onlyOwner noReentrant {
        require(block.timestamp < deadline, "Use regular withdraw after deadline");
        require(receivedAmount >= goal, "Goal not reached yet");
        
        uint256 availableToWithdraw = receivedAmount - withdrawnAmount;
        require(availableToWithdraw > 0, "No funds available to withdraw");
        
        withdrawnAmount += availableToWithdraw;
        
        (bool sent, ) = payable(owner).call{value: availableToWithdraw}("");
        require(sent, "Failed to withdraw funds");
        
        emit FundsWithdrawn(owner, availableToWithdraw, true, false);
    }

    // Regular withdraw after deadline - with goal check
    function withdraw() public onlyOwner noReentrant {
        require(block.timestamp >= deadline, "Cannot withdraw before deadline");
        require(receivedAmount >= goal, "Goal not reached yet");
        
        uint256 availableToWithdraw = receivedAmount - withdrawnAmount;
        require(availableToWithdraw > 0, "No funds available to withdraw");
        
        withdrawnAmount += availableToWithdraw;
        
        (bool sent, ) = payable(owner).call{value: availableToWithdraw}("");
        require(sent, "Failed to withdraw funds");
        
        emit FundsWithdrawn(owner, availableToWithdraw, false, false);
    }

    // Withdraw without goal requirement (if partial funding is acceptable)
    function withdrawPartialFunding() public onlyOwner noReentrant {
        require(block.timestamp >= deadline, "Cannot withdraw before deadline");
        
        uint256 availableToWithdraw = receivedAmount - withdrawnAmount;
        require(availableToWithdraw > 0, "No funds available to withdraw");
        require(availableToWithdraw >= 0.001 ether, "Withdrawal amount too small");
        
        withdrawnAmount += availableToWithdraw;
        
        (bool sent, ) = payable(owner).call{value: availableToWithdraw}("");
        require(sent, "Failed to withdraw funds");
        
        emit FundsWithdrawn(owner, availableToWithdraw, false, true);
    }

    // Combined campaign management function
    function manageCampaign(bool pauseState, uint256 daysToAdd) public onlyOwner {
        // Toggle pause state if needed
        if (paused != pauseState) {
            paused = pauseState;
            emit CampaignPaused(paused);
        }
        
        // Extend deadline if requested
        if (daysToAdd > 0) {
            require(
                block.timestamp < deadline,
                "Cannot extend deadline if it has already reached"
            );
            require(daysToAdd <= 365, "Cannot extend deadline by more than 1 year");
            deadline += daysToAdd * 1 days;
            emit DeadlineExtended(deadline);
        }
    }

    // Get campaign details
    function getCampaignDetails() public view returns (
        address campaignOwner,
        string memory campaignTitle,
        string memory campaignDescription,
        uint256 campaignGoal,
        uint256 currentAmount,
        uint256 campaignDeadline,
        bool isCampaignPaused,
        bool hasMetDeadline,
        bool hasMetGoal
    ) {
        return (
            owner,
            title,
            description,
            goal,
            receivedAmount,
            deadline,
            paused,
            block.timestamp >= deadline,
            receivedAmount >= goal
        );
    }
    
    // Get backer information
    function getBackerInfo(address backer) public view returns (
        uint256 totalContribution
    ) {
        return backers[backer].totalContribution;
    }

    // Check status of a cross-chain donation
    function getCrossChainDonationStatus(bytes32 messageId) public view returns (
        address donor,
        uint256 amount,
        uint256 timestamp,
        bool completed
    ) {
        CrossChainDonation memory donation = pendingCrossChainDonations[messageId];
        require(donation.donor != address(0), "Donation not found");
        return (donation.donor, donation.amount, donation.timestamp, donation.completed);
    }
}