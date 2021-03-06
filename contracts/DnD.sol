// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@unification-com/xfund-vor/contracts/VORConsumerBase.sol";

/** ****************************************************************************
 * @notice Extremely simple DnD roll D20 to Hit using VOR
 * *****************************************************************************
 * @dev The contract owner can add up to 20 monsters. Players can modify their STR
 * modifier, which is pinned to their address. Players call the rollForHit function
 * and pay the associated xFUND fee to roll the D20. The result is returned in
 * fulfillRandomness, which calculates if the player crits, hits or misses.
 */
contract DnD is Ownable, VORConsumerBase {
    using SafeMath for uint256;

    // keep track of the monsters
    uint256 public nextMonsterId;

    // super simple monster stats
    struct Monster {
        string name;
        uint256 ac;
    }

    struct Result {
        uint256 roll;
        uint256 modified;
        string result;
        bool isRolling;
    }

    // monsters held in the contract
    mapping (uint256 => Monster) public monsters;
    // player STR modifiers
    mapping (address => uint256) public strModifiers;
    // map request IDs to monster IDs
    mapping(bytes32 => uint256) public requestIdToMonsterId;
    // map request IDs to player addresses, to retrieve STR modifiers
    mapping(bytes32 => address) public requestIdToAddress;
    // store last [player][monster] results
    mapping(address => mapping(uint256 => Result)) lastResult;

    // Some useful events to track
    event AddMonster(uint256 monsterId, string name, uint256 ac);
    event ChangeStrModifier(address player, uint256 strMod);
    event HittingMonster(uint256 monsterId, bytes32 requestId);
    event HitResult(uint256 monsterId, bytes32 requestId, address player, string result, uint256 roll, uint256 modified);

    /**
    * @notice Constructor inherits VORConsumerBase
    *
    * @param _vorCoordinator address of the VOR Coordinator
    * @param _xfund address of the xFUND token
    */
    constructor(address _vorCoordinator, address _xfund)
    public
    VORConsumerBase(_vorCoordinator, _xfund) {
        nextMonsterId = 1;
    }

    /**
    * @notice addMonster can be called by the owner to add a new monster
    *
    * @param _name string name of the monster
    * @param _ac uint256 AC of the monster
    */
    function addMonster(string memory _name, uint256 _ac) external onlyOwner {
        require(nextMonsterId <= 20, "too many monsters");
        require(_ac > 0, "monster too weak");
        monsters[nextMonsterId].name = _name;
        monsters[nextMonsterId].ac = _ac;
        emit AddMonster(nextMonsterId, _name, _ac);
        nextMonsterId = nextMonsterId.add(1);
    }

    /**
    * @notice changeStrModifier can be called by anyone to change their STR modifier
    *
    * @param _strMod uint256 STR modifier of player
    */
    function changeStrModifier(uint256 _strMod) external {
        require(_strMod <= 5, "player too strong");
        strModifiers[msg.sender] = _strMod;
        emit ChangeStrModifier(msg.sender, _strMod);
    }

    /**
    * @notice rollForHit anyone can call to roll the D20 for hit. Caller (msg.sender)
    * pays the xFUND fees for the request.
    *
    * @param _monsterId uint256 Id of the monster the caller is fighting
    * @param _seed uint256 seed for the randomness request. Gets mixed in with the blockhash of the block this Tx is in
    * @param _keyHash bytes32 key hash of the provider caller wants to fulfil the request
    * @param _fee uint256 required fee amount for the request
    */
    function rollForHit(uint256 _monsterId, uint256 _seed, bytes32 _keyHash, uint256 _fee) external returns (bytes32 requestId) {
        require(monsters[_monsterId].ac > 0, "monster does not exist");
        require(!lastResult[msg.sender][_monsterId].isRolling, "roll currently in progress");
        // Note - caller must have increased xFUND allowance for this contract first.
        // Fee is transferred from msg.sender to this contract. The VORCoordinator.requestRandomness
        // function will then transfer from this contract to itself.
        // This contract's owner must have increased the VORCoordnator's allowance for this contract.
        xFUND.transferFrom(msg.sender, address(this), _fee);
        requestId = requestRandomness(_keyHash, _fee, _seed);
        emit HittingMonster(_monsterId, requestId);
        requestIdToAddress[requestId] = msg.sender;
        requestIdToMonsterId[requestId] = _monsterId;
        lastResult[msg.sender][_monsterId].isRolling = true;
    }

    /**
     * @notice Callback function used by VOR Coordinator to return the random number
     * to this contract.
     * @dev The random number is used to simulate a D20 roll. Result is emitted as follows:
     * 1: Natural 1...
     * 20: Natural 20!
     * roll + strModifier >= monster AC: hit
     * roll + strModifier < monster AC: miss
     *
     * @param _requestId bytes32
     * @param _randomness The random result returned by the oracle
     */
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        uint256 monsterId = requestIdToMonsterId[_requestId];
        address player = requestIdToAddress[_requestId];
        uint256 strModifier = strModifiers[player];
        uint256 roll = _randomness.mod(20).add(1);
        uint256 modified = roll.add(strModifier);
        string memory res = "miss";

        // Critical hit!
        if(roll == 20) {
            res = "nat20";
        } else if (roll == 1) {
            res = "nat1";
        } else {
            // Check roll + STR modifier against monster's AC
            if(modified >= monsters[monsterId].ac) {
                res = "hit";
            } else {
                res = "miss";
            }
        }
        emit HitResult(monsterId, _requestId, player, res, roll, modified);

        // store the results
        lastResult[player][monsterId].result = res;
        lastResult[player][monsterId].roll = roll;
        lastResult[player][monsterId].modified = modified;
        lastResult[player][monsterId].isRolling = false;

        // clean up
        delete requestIdToMonsterId[_requestId];
        delete requestIdToAddress[_requestId];
    }

    /**
     * @notice getLastResult returns the last result for a specified player/monsterId.
     *
     * @param _player address address of player
     * @param _monsterId uint256 id of monster
     */
    function getLastResult(address _player, uint256 _monsterId) external view returns (Result memory) {
        return lastResult[_player][_monsterId];
    }

    /**
    * @notice unstickRoll allows contract owner to unstick a roll when a request is not fulfilled
    *
    * @param _player address address of player
    * @param _monsterId uint256 id of monster
    */
    function unstickRoll(address _player, uint256 _monsterId) external onlyOwner {
        lastResult[_player][_monsterId].isRolling = false;
    }

    /**
     * @notice Example wrapper function for the VORConsumerBase increaseVorCoordinatorAllowance function.
     * @dev Wrapped around an Ownable modifier to ensure only the contract owner can call it.
     * @dev Allows contract owner to increase the xFUND allowance for the VORCoordinator contract
     * @dev enabling it to pay request fees on behalf of this contract.
     *
     * @param _amount uint256 amount to increase allowance by
     */
    function increaseVorAllowance(uint256 _amount) external onlyOwner {
        _increaseVorCoordinatorAllowance(_amount);
    }

    /**
     * @notice Example wrapper function for the VORConsumerBase withdrawXFUND function.
     * Wrapped around an Ownable modifier to ensure only the contract owner can call it.
     * Allows contract owner to withdraw any xFUND currently held by this contract
     */
    function withdrawToken(address to, uint256 value) external onlyOwner {
        require(xFUND.transfer(to, value), "Not enough xFUND");
    }

    /**
     * @notice Example wrapper function for the VORConsumerBase _setVORCoordinator function.
     * Wrapped around an Ownable modifier to ensure only the contract owner can call it.
     * Allows contract owner to change the VORCoordinator address in the event of a network
     * upgrade.
     */
    function setVORCoordinator(address _vorCoordinator) external onlyOwner {
        _setVORCoordinator(_vorCoordinator);
    }

    /**
     * @notice returns the current VORCoordinator contract address
     * @return vorCoordinator address
     */
    function getVORCoordinator() external view returns (address) {
        return vorCoordinator;
    }
}
