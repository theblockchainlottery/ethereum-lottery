pragma solidity ^0.5.2;

import "github.com/OpenZeppelin/zeppelin-solidity/contracts/math/SafeMath.sol";

contract Lottery {
    using SafeMath for uint; 
    
    address payable public owner;
    address payable public winner;
    
    bool public isFunding;
    bool private numberGen;
    bool private endDrawCall;
    
    uint private randomNumber;
    uint private startTime;
    uint private endTime;
    uint private timeInterval;
    uint private previousDraws;
    uint private biggestWinnings;
    uint private overallWinnings;
    uint private winnerBalance;
    uint private maxRange;
    uint private minRange;
    uint private offset;
    uint private ticketPrice;
    uint private userNumGen;
    
    struct Entry {
        uint drawID; // unique ID
        address payable wallet; // Entry wallet address
        uint randomNum; // number selected by user on entry
        bool entered;  // if true, this person already entered
    }
    
    // if applied to a function it can only be called by contract owner
    modifier onlyOwner { 
        require(msg.sender == owner);
        _;
    }
    
    mapping (address => Entry) private entries;
    address payable []entryAddresses;
    uint numAddresses = 0;
    
    //EVENTS /////////////////////////////////////////////////////////////////////////
     event DrawStarted(string message);
     event TicketBought(address from, string message); //new entry
     event EthReleased(uint256 amount, string message, address winner); //draw end
     event NoEntries(string message);
     event EntryIDLog(uint id, uint rand, uint offset);
     event ContractMsg(string message);
     event DrawExtended(uint timeSinceExpiry, string message);
     event Refund(uint entries, string message);
    //CONSTRUCTOR (called on contract creation) //////////////////////////////////////
    constructor (uint drawLengthInSeconds) public {
        owner = msg.sender;
        timeInterval = SafeMath.div(drawLengthInSeconds, 1 seconds); // draw length 604800 secs for 1 week
        startTime = now; //set startTime , now is alias for block.timestamp (seconds since unix epoch)
        endTime = SafeMath.add(startTime, timeInterval); // set endTime
        ticketPrice = 10000000000000000;//wei
        startDraw();
    }
    
    function startDraw() internal onlyOwner {
        isFunding = true; 
        numberGen = false;
        randomNumber = 0;
        startTime = now; //now is alias for block.timestamp
        endTime = SafeMath.add(startTime, timeInterval); // set endTime
        emit DrawStarted("Draw Started");
    }
    
      //get balance of contract
    function contractBalance() public view returns(uint) {
        address contractAddress = address(this);
        return contractAddress.balance;
    }
    
    //returns current block.timestamp
    function getNowTime() public view returns (uint) {
        return now;
    }
    
    //returns end time(seconds since unix epoch)
    function getEndTime() public view returns (uint) {
        return endTime;
    }
    
     //returns draw length in seconds
    function getTimeInterval() public view returns(uint) {
        return timeInterval;
    }
    
    //returns amount of time passed in seconds
    function getTimePassed() public view returns (uint) {
        require(startTime != 0);
        return SafeMath.div(SafeMath.sub(now, startTime),1 seconds);
    }
    
    //returns the amount of time left in seconds
    function getTimeLeft() public view returns (uint) {
        require(endTime > now);
        return SafeMath.div(SafeMath.sub(endTime, now),1 seconds);
    }
    
    //refund all funds back to users (precautionary measure to be used only ever in the event of a locked/broken contract)
    function fixBrokenContract(bool _destroy) public onlyOwner {
        require(contractBalance() > 0 && now > endTime);
            isFunding = false;
            uint refundAmount = SafeMath.div(contractBalance(), numAddresses);
            uint endArray = entryAddresses.length;
            uint startArray = SafeMath.sub(endArray, numAddresses);
            //could be problematic after many draws / high entry amount
            for (uint i = startArray; i < endArray; i++) {
                if(contractBalance() < ticketPrice) {
                    refundAmount = contractBalance();
                }
                //reset variables to simulate restart conditions
                entries[entryAddresses[i]].entered = false;
                entries[entryAddresses[i]].randomNum = 0;
                entries[entryAddresses[i]].drawID = 0;
                //make transfer 
                entries[entryAddresses[i]].wallet.transfer(refundAmount);
            }
            emit Refund(numAddresses, "- users refunded");   //emitevent
        //destroy contract if specified
        if(_destroy) {
            selfdestruct(owner);
        }
        else{
            //reset variables to simulate restart conditions
            endDrawCall = true;
            userNumGen = 0;
            numAddresses = 0;
            numberGen = true;
            restartDraw();
        }
    }
    
    //fallback function in the case funds are transferred directly to the contract address(draw participation still applicable)
    function() external payable {
        buyTicket(1);
    }
    
    //buy lottery ticket
    function buyTicket(uint _randomNum) public payable {
        //check if draw open & user input number is within range
        require(isFunding && _randomNum >= 1 && _randomNum <= 100);
        //check if user is sending the correct amount
        require(msg.value > 0 && msg.value == ticketPrice);
        //check if user has already entered
        require(entries[msg.sender].entered == false);
        //increment number of entry addresses
        numAddresses = SafeMath.add(numAddresses,1);
        //map user address into Entry struct
        Entry storage _ent = entries[msg.sender];
        //input data to stuct
       _ent.drawID = SafeMath.sub(numAddresses, 1);//set user ID 
       _ent.wallet = msg.sender;//set user address
       _ent.randomNum = _randomNum;
       _ent.entered = true;//set has entered (used to block multiple entries from same address)
       //add user address to entryAddress array
        entryAddresses.push(msg.sender);
        emit TicketBought(msg.sender,"Ticket Bought, New Entry!");
        // if draw time expired, stop funding & make call to oraclize for random number generation
        if(now > endTime) {
            //if first entry is after draw expiry, extend draw runtime
            if(getEntryCount() == 1){
                uint expiredTime = SafeMath.sub(now, endTime);
                startTime = now; //set new startTime , now is alias for block.timestamp (seconds since unix epoch)
                endTime = SafeMath.add(startTime, timeInterval); // set new endTime
                emit DrawExtended(expiredTime, "- expired draw before first entry - Draw Extended");
                expiredTime = 0;
            } else {
                emit ContractMsg("Ending Draw...");
                this.endDraw();
            }
        }
    }

    //returns Entry struct data (check if specific address has entered)
    function getAddressInfo(address u) view public returns (address, bool) {
        return (entries[u].wallet, entries[u].entered);
    }
    
    //returns Entry struct data (get address of a specific id)
    function getEntryAddressById(uint _id) public view returns(uint, address) {
        require(numAddresses > 0 && _id <= numAddresses);
        uint temp = SafeMath.add(_id, SafeMath.sub(entryAddresses.length, numAddresses));
        return (entries[entryAddresses[temp]].drawID, entries[entryAddresses[temp]].wallet);
    }
    
    //number of active entries (current draw)
    function getEntryCount() view public returns (uint) {
        return numAddresses;
    }
    
    //returns address of last draw winner
    function getLastWinner() view public returns (address) {
        return winner;
    }
    
    //returns winnings of last draw
    function getLastWinnings() view public returns (uint) {
        return winnerBalance;
    }
    
    //returns largest winnings from all draws
    function getBiggestWinnings() view public returns (uint) {
        return biggestWinnings;
    }
    
    //returns overall winnings throughout all draws
    function getOverallWinnings() view public returns (uint) {
        return overallWinnings;
    }
    
    //number of previous finished draws
    function getPreviousDraws() view public returns(uint) {
        return previousDraws;
    }

    //dissallow new entries into the draw 
    function endDraw() payable external {
        require(isFunding && contractBalance() > 0 && now > endTime);
        isFunding = false;
        numberGen = false;
        generateRandomNumber();
    }
    
    //converts uint to bytes
    function toBytes(uint256 x) private pure returns (bytes memory b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }
    
    // random number generation
    function generateRandomNumber() internal { 
        // If we already generated a random number, we can't generate a new one.
        require(!numberGen && !isFunding);
            uint endArray = entryAddresses.length;
            uint startArray = SafeMath.sub(endArray, numAddresses);
            //could be problematic after many draws / high entry amount
            for (uint i = startArray; i < endArray; i++) {
                //add the user selected numbers to eachother
               userNumGen = SafeMath.add(userNumGen, entries[entryAddresses[i]].randomNum);
            }
            //convert to bytes
            bytes memory userNumBytes = toBytes(userNumGen);
            // convert bytes to random uint
            randomNumber = uint(keccak256(userNumBytes));
            numberGen = true;
             // random number was generated
            emit ContractMsg("Random Num Generated");
            endDrawCall = true;
            calculatePreviousDraws();
    }

    //calculate amount of prevoius draws
    function calculatePreviousDraws() internal {
        require(numberGen && !isFunding && endDrawCall);
        previousDraws = SafeMath.add(previousDraws,1);
        setWinnings();
    }
    
    //calulate winnings & winner
    function setWinnings() internal {
        require(numberGen && !isFunding && endDrawCall);
        if (contractBalance() > 0) {
           uint winningNumber;
           setWinnerRange();
           if (maxRange == 0) {
               winningNumber = 0;
           } else {
               //calculate winningNumber
               winningNumber = SafeMath.mod(randomNumber, maxRange);
           }
           winner = pickWinner(winningNumber);
           uint winnings = contractBalance();
           uint devWinnings = SafeMath.div(winnings, 200); //calculate dev funds 0.5%
           winnerBalance = SafeMath.sub(winnings, devWinnings);//calculate winner funds
           overallWinnings = SafeMath.add(overallWinnings, winnerBalance);
           if (winnerBalance > biggestWinnings) {
               biggestWinnings = winnerBalance;
           }
           releaseEth(devWinnings);
           refreshUsers();//clear contributors
           emit EthReleased(winnerBalance,"Draw Finished, Ether Released! Winner is - ", winner);//event
           restartDraw();
        } else {
           emit NoEntries("Draw Finished, No Entries");
           restartDraw();
        }
    }
    
    //set uint range 
    function setWinnerRange() internal {
        require(numberGen && !isFunding && endDrawCall);
        offset = SafeMath.sub(entryAddresses.length, numAddresses); //set offset
        maxRange = SafeMath.sub(entryAddresses.length, offset); //sets min/max range to make min 0 and max relative offset
        minRange = 0;
    }
    
    //pick winning address
    function pickWinner(uint winNum) internal returns (address payable) {
        require(numberGen && !isFunding && endDrawCall);
        uint winnerNum = SafeMath.add(winNum, offset);
        address payable selection = entryAddresses[winnerNum];
        emit EntryIDLog(entries[entryAddresses[winnerNum]].drawID, winnerNum, (offset));
        return (selection);
    }
   
    //release Eth to winner / winner&dev
    function releaseEth(uint devBalance) internal {
        require(numberGen && !isFunding && endDrawCall);
        owner.transfer(devBalance);
        winner.transfer(winnerBalance);
    }
    
    //clear users ready for next draw
    function refreshUsers() internal {
        require(numberGen && !isFunding && endDrawCall);
        uint endArray = entryAddresses.length;
        uint startArray = SafeMath.sub(endArray, numAddresses);
        //could be problematic after many draws / high entry amount
        for (uint i = startArray; i < endArray; i++) {
           entries[entryAddresses[i]].entered = false;
           entries[entryAddresses[i]].randomNum = 0;
           entries[entryAddresses[i]].drawID = 0;
        }
        userNumGen = 0;
        numAddresses = 0;
        //possibly better option to delete entire array after every draw
        /*for(uint i = startArray; i < endArray; i++){
            delete entryAddresses[i];
        }
        numAddresses = 0;*/
    }
    
    //restart lottery
    function restartDraw() internal {
        require(numberGen && !isFunding && endDrawCall);
        isFunding = true; 
        numberGen = false;
        endDrawCall = false;
        randomNumber = 0;
        startTime = now; //now is alias for block.timestamp
        endTime = SafeMath.add(startTime, timeInterval); // set new endTime
        emit DrawStarted("Draw Re-Started");
    }
}
