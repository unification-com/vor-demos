// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@unification-com/xfund-vor/contracts/VORConsumerBase.sol";

/** ****************************************************************************
 * @notice Demo NFT competition using VOR
 * *****************************************************************************
 * @dev PURPOSE
 *
 * @dev The contract owner can run any number of competitions with NFTs as
 * @dev prizes. Entrants pay an xFUND fee to enter, and when the competition
 * @dev runs, the winner is selected by requesting randomness from a VOR
 * @dev oracle. The NFT is transferred to the winner.
 */

contract NFTCompetition is Ownable, ERC721, VORConsumerBase, IERC721Receiver {

    using SafeMath for uint256;
    using Address for address;

    bytes32 internal keyHash; // keyHash for randomess provider
    uint256 internal randomnessFee; // fee charged by randomness provider

    uint256 internal currentCompetitionId;

    struct Competition {
        uint256 maxEntries; // max number of entries allowed
        uint256 competitionFee; // xFUND cost to enter competition
        uint256 tokenId; //will be the same as the competitionId
        bool open;
        bool running;
        address[] entrants;
    }

    mapping(uint256 => Competition) public competitions;
    mapping(bytes32 => uint256) public requestIdToCompetitionId;

    event NewCompetition(uint256 Id, address indexed creator);
    event CompetitionEntry(uint256 competitionId, address indexed entrant);
    event CompetitionRunning(uint256 competitionId, bytes32 requestId);
    event CompetitionWinner(uint256 competitionId, address indexed winner, bytes32 requestId);
    event ERC721Received(address operator, address from, uint256 tokenId);

    /**
    * @notice Constructor inherits VORConsumerBase
    *
    *
    * @param _vorCoordinator address of the VOR Coordinator
    * @param _xfund address of the xFUND token
    * @param _keyHash bytes32 representing the hash of the VOR provider
    * @param _randomnessFee uint256 fee to pay the VOR oracle
    * @param _name string name of the NFT token
    * @param _symbol string symbol of the NFT token
    */
    constructor(
        address _vorCoordinator,
        address _xfund,
        bytes32 _keyHash,
        uint256 _randomnessFee,
        string memory _name,
        string memory _symbol
    )
    public
    VORConsumerBase(_vorCoordinator, _xfund)
    ERC721(_name, _symbol)
    {
        keyHash = _keyHash;
        randomnessFee = _randomnessFee;

        currentCompetitionId = 1;
    }

    /**
    * @notice Creates a new competition and mints the NFT. This contract is the temporary owner
    *
    * @param _nftUri string URI of the NFT being offered as a prize
    * @param _maxEntries uint256 max number of entries for this competition
    * @param _competitionFee uint256 xFUND fee for entering
    */
    function newCompetition(string memory _nftUri, uint256 _maxEntries, uint256 _competitionFee) external onlyOwner {

        _safeMint(address(this), currentCompetitionId);
        _setTokenURI(currentCompetitionId, _nftUri);

        competitions[currentCompetitionId].maxEntries = _maxEntries;
        competitions[currentCompetitionId].tokenId = currentCompetitionId;
        competitions[currentCompetitionId].competitionFee = _competitionFee;
        competitions[currentCompetitionId].open = true;
        competitions[currentCompetitionId].running = false;

        emit NewCompetition(currentCompetitionId, msg.sender);

        currentCompetitionId = currentCompetitionId.add(1);
    }

    /**
     * @notice Enters an address into the selected competition, and deducts xFUND fees
     *
     * @param _competitionId uint256 ID of the competition being run
     */
    function enterCompetition(uint256 _competitionId) external {
        require(competitions[_competitionId].open, "competition does not exist");
        require(competitions[_competitionId].entrants.length < competitions[_competitionId].maxEntries, "competition full");

        uint256 fee = competitions[_competitionId].competitionFee;

        xFUND.transferFrom(msg.sender, address(this), fee);

        competitions[_competitionId].entrants.push(msg.sender);

        emit CompetitionEntry(_competitionId, msg.sender);
    }

    /**
     * @notice Requests randomness from a user-provided seed for the selected competition
     *
     * @param _userProvidedSeed uint256 unpredictable seed
     * @param _competitionId uint256 ID of the competition being run
     */
    function runCompetition(uint256 _userProvidedSeed, uint256 _competitionId) external onlyOwner returns (bytes32 requestId) {
        require(competitions[_competitionId].open, "competition does not exist");
        competitions[_competitionId].open = false;
        competitions[_competitionId].running = true;
        xFUND.transferFrom(msg.sender, address(this), randomnessFee);
        requestId = requestRandomness(keyHash, randomnessFee, _userProvidedSeed);
        requestIdToCompetitionId[requestId] = _competitionId;
        emit CompetitionRunning(_competitionId, requestId);
    }

    /**
     * @notice Callback function used by VOR Coordinator to return the random number
     * to this contract.
     * @dev The random number is used to select the winner of the running NFT competition.
     * The NFT is then transferred to the winner.
     *
     * @param _requestId bytes32
     * @param _randomness The random result returned by the oracle
     */
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        uint256 competitionId = requestIdToCompetitionId[_requestId];
        require(competitions[competitionId].running, "competition not running");
        competitions[competitionId].running = false;
        uint256 winnerIdx = _randomness.mod(competitions[competitionId].entrants.length);
        address winner = competitions[competitionId].entrants[winnerIdx];

        _safeTransfer(address(this), winner, competitions[competitionId].tokenId, "");

        emit CompetitionWinner(competitionId, winner, _requestId);

        delete competitions[competitionId];
        delete requestIdToCompetitionId[_requestId];
    }

    /**
     * @notice Example wrapper function for the VORConsumerBase increaseVorCoordinatorAllowance function.
     * @dev Wrapped around an Ownable modifier to ensure only the contract owner can call it.
     * @dev Allows contract owner to increase the xFUND allowance for the VORCoordinator contract
     * @dev enabling it to pay request fees on behalf of this contract's owner.
     * @dev NOTE: This contract must have an xFUND balance in order to request randomness
     *
     * @param _amount uint256 amount to increase allowance by
     */
    function increaseVorAllowance(uint256 _amount) external onlyOwner {
        _increaseVorCoordinatorAllowance(_amount);
    }

    /**
     * @notice withdrawToken allow contract owner to withdraw xFUND from this contract
     * @dev Wrapped around an Ownable modifier to ensure only the contract owner can call it.
     * @dev Allows contract owner to withdraw any xFUND currently held by this contract
     */
    function withdrawToken(address to, uint256 value) external onlyOwner {
        require(xFUND.transfer(to, value), "not enough xFUND");
    }

    /**
     * @notice Set the key hash for the oracle
     *
     * @param _keyHash bytes32 key hash of the oracle fulfilling requests
     */
    function setKeyHash(bytes32 _keyHash) public onlyOwner {
        keyHash = _keyHash;
    }

    /**
     * @notice Set the randomness fee for the oracle
     *
     * @param _randomnessFee uint256 fee to be paid to oracle for requests
     */
    function setRandomnessFee(uint256 _randomnessFee) public onlyOwner {
        randomnessFee = _randomnessFee;
    }

    /**
     * @notice Get a competition's data
     *
     * @param _competitionId uint256 ID of the competition
     */
    function getCompetition(uint256 _competitionId) public view returns(Competition memory) {
        return competitions[_competitionId];
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        emit ERC721Received(operator, from, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}
