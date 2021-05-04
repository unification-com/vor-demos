// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@unification-com/xfund-vor/contracts/VORConsumerBase.sol";

/** ****************************************************************************
 * @notice Simple Dungeon Encounter using VOR
 * *****************************************************************************
 * @dev The contract owner can add up to 20 monsters. Players can initialise a
 * combat encounter with any selected monster. Players roll each round of combat
 * until the encounter is resolved.
 */
contract DungeonEncounters is Ownable, VORConsumerBase {
    using SafeMath for uint256;

    // keep track of the monster IDs
    uint256 public nextMonsterId;
    uint256 public statFee;
    uint256 public healingPotionFee;
    uint256 private withdrawableFees;

    uint256 private constant PLAYER_START_AC = 15; // base armour class
    uint256 private constant PLAYER_START_HP = 30; // base hit points
    uint256 private constant PLAYER_START_STR = 0; // base STR modifier (applied to hit rolls)
    uint256 private constant PLAYER_START_ATK = 6; // base ATK dice
    uint256 private constant PLAYER_START_DMG = 0; // base DMG modifier (applied to dmg roll)

    uint256 public maxPlayerAc;
    uint256 public maxPlayerHp;
    uint256 public maxPlayerStr;
    uint256 public maxPlayerAtk;
    uint256 public maxPlayerDmg;
    uint256 public healingPotionHp;
    uint256 public maxHealingPotions;

    // Monster stats
    struct Monster {
        string name;
        uint256 ac;
        uint256 hp;
        uint256 str;
        uint256 atk;
        uint256 dmg;
    }

    // Player stats
    struct Player {
        string name;
        uint256 ac;
        uint256 hp;
        uint256 str;
        uint256 atk;
        uint256 dmg;
        uint256 healingPotions;
        uint256 won;
        uint256 lost;
        bool inEncounter;
    }

    // Encounter data
    struct Encounter {
        address player;
        uint256 monsterId;
        uint256 monsterHp;
        uint256 playerHp;
        bool isRolling;
    }

    // monsters held in the contract
    mapping (uint256 => Monster) public monsters;
    // players held in the contract
    mapping (address => Player) public players;
    // encounters in progress
    mapping (bytes32 => Encounter) public encounters;
    // map request IDs to encounter IDs
    mapping(bytes32 => bytes32) public requestIdToEncounterId;

    // Some useful events to track
    event AddMonster(uint256 monsterId, string name, uint256 ac, uint256 hp, uint256 str, uint256 atk, uint256 dmg);
    event CreatePlayer(address player, string name, uint256 ac, uint256 hp, uint256 str, uint256 atk);
    event StartEncounter(bytes32 indexed encounterId, address player, uint256 monsterId);
    event CombatRoundInitialised(bytes32 indexed encounterId, bytes32 requestId);
    event PlayerResult(bytes32 indexed encounterId, address player, uint256 roll, uint256 modified, bool hit, bool isCrit, uint256 damage, uint256 monsterHp);
    event MonsterResult(bytes32 indexed encounterId, uint256 monsterId, uint256 roll, uint256 modified, bool hit, bool isCrit, uint256 damage, uint256 playerHp);
    event EncounterOver(bytes32 indexed encounterId, bool playerWon);
    event SetStatFee(uint256 oldFee, uint256 newFee);
    event SetHealingPotionFee(uint256 oldFee, uint256 newFee);
    event StatIncreased(address player, string stat, uint256 newValue, uint256 feePaid);
    event BoughtHealingPotion(address player, uint256 feePaid);
    event DrankHealingPotion(address player, uint256 newHp);
    event MaxStatIncreased(string stat, uint256 newValue);

    /**
    * @notice Constructor inherits VORConsumerBase
    *
    * @param _vorCoordinator address of the VOR Coordinator
    * @param _xfund address of the xFUND token
    */
    constructor(address _vorCoordinator, address _xfund, uint256 _statFee, uint256 _healingPotionFee)
    public
    VORConsumerBase(_vorCoordinator, _xfund) {
        nextMonsterId = 1;
        statFee = _statFee;
        healingPotionFee = _healingPotionFee;
        maxPlayerAc = 25;
        maxPlayerHp = 100;
        maxPlayerStr = 10;
        maxPlayerAtk = 12;
        maxPlayerDmg = 10;
        healingPotionHp = 20;
        maxHealingPotions = 5;
    }

    /**
    * @notice addMonster can be called by the owner to add a new monster
    *
    * @param _name string name of the monster
    * @param _ac uint256 AC of the monster
    */
    function addMonster(string memory _name, uint256 _ac, uint256 _hp, uint256 _str, uint256 _atk, uint256 _dmg) external onlyOwner {
        require(nextMonsterId <= 20, "too many monsters");
        require(_ac > 0 && _hp > 0, "monster too weak");
        require(_atk == 4 || _atk == 6 || _atk == 8 || _atk == 10 || _atk == 12, "invalid atk dice");
        monsters[nextMonsterId].name = _name;
        monsters[nextMonsterId].ac = _ac;
        monsters[nextMonsterId].hp = _hp;
        monsters[nextMonsterId].str = _str;
        monsters[nextMonsterId].atk = _atk;
        monsters[nextMonsterId].dmg = _dmg;
        emit AddMonster(nextMonsterId, _name, _ac, _hp, _str, _atk, _dmg);
        nextMonsterId = nextMonsterId.add(1);
    }

    /**
     * @notice setStatIncreaseFee allows contract owner to set xFUND fee
     * players must pay to increase their stats
     *
     * @param _newStatFee uint256 new fee
     */
    function setStatIncreaseFee(uint256 _newStatFee) external onlyOwner {
        require(_newStatFee > 0, "fee cannot be zero");
        uint256 oldFee = statFee;
        statFee = _newStatFee;
        emit SetStatFee(oldFee, _newStatFee);
    }

    /**
     * @notice setHealingPotionFee allows contract owner to set xFUND fee
     * players must pay to buy a healing potion
     *
     * @param _newFee uint256 new fee
     */
    function setHealingPotionFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "fee cannot be zero");
        uint256 oldFee = healingPotionFee;
        healingPotionFee = _newFee;
        emit SetHealingPotionFee(oldFee, _newFee);
    }

    /**
     * @notice setMaxPlayerAc allows contract owner to increase max stat
     *
     * @param _newMaxPlayerAc uint256 new max
     */
    function setMaxPlayerAc(uint256 _newMaxPlayerAc) external onlyOwner {
        require(_newMaxPlayerAc > maxPlayerAc, "must increase");
        maxPlayerAc = _newMaxPlayerAc;
        emit MaxStatIncreased("AC", _newMaxPlayerAc);
    }

    /**
     * @notice setMaxPlayerHp allows contract owner to increase max stat
     *
     * @param _newMaxPlayerHp uint256 new max
     */
    function setMaxPlayerHp(uint256 _newMaxPlayerHp) external onlyOwner {
        require(_newMaxPlayerHp > maxPlayerHp, "must increase");
        maxPlayerHp = _newMaxPlayerHp;
        emit MaxStatIncreased("HP", _newMaxPlayerHp);
    }

    /**
     * @notice setMaxPlayerStr allows contract owner to increase max stat
     *
     * @param _newMaxPlayerStr uint256 new max
     */
    function setMaxPlayerStr(uint256 _newMaxPlayerStr) external onlyOwner {
        require(_newMaxPlayerStr > maxPlayerStr, "must increase");
        maxPlayerStr = _newMaxPlayerStr;
        emit MaxStatIncreased("STR", _newMaxPlayerStr);
    }

    /**
     * @notice setMaxPlayerAtk allows contract owner to increase max stat
     *
     * @param _newMaxPlayerAtk uint256 new max
     */
    function setMaxPlayerAtk(uint256 _newMaxPlayerAtk) external onlyOwner {
        require(_newMaxPlayerAtk > maxPlayerAtk, "must increase");
        maxPlayerAtk = _newMaxPlayerAtk;
        emit MaxStatIncreased("ATK", _newMaxPlayerAtk);
    }

    /**
     * @notice setMaxPlayerDmg allows contract owner to increase max stat
     *
     * @param _newMaxPlayerDmg uint256 new max
     */
    function setMaxPlayerDmg(uint256 _newMaxPlayerDmg) external onlyOwner {
        require(_newMaxPlayerDmg > maxPlayerDmg, "must increase");
        maxPlayerDmg = _newMaxPlayerDmg;
        emit MaxStatIncreased("DMG", _newMaxPlayerDmg);
    }

    /**
     * @notice setHealingPotionHp allows contract owner to change amount
     * of HP a healing potion provides
     *
     * @param _newHealingPotionHp uint256 new value
     */
    function setHealingPotionHp(uint256 _newHealingPotionHp) external onlyOwner {
        require(_newHealingPotionHp > 0, "must be > zero");
        healingPotionHp = _newHealingPotionHp;
        emit MaxStatIncreased("HealingPotionHP", _newHealingPotionHp);
    }

    /**
    * @notice createPlayer can be called by any wallet to create a new basic player
    * PLAYER_START_* consts are used for initial player stats
    *
    * @param _name string name of the player
    */
    function createPlayer(string memory _name) external {
        require(players[msg.sender].ac == 0, "player exists");

        players[msg.sender].name = _name;
        players[msg.sender].ac = PLAYER_START_AC;
        players[msg.sender].hp = PLAYER_START_HP;
        players[msg.sender].str = PLAYER_START_STR;
        players[msg.sender].atk = PLAYER_START_ATK;
        players[msg.sender].dmg = PLAYER_START_DMG;
        players[msg.sender].healingPotions = 0;
        players[msg.sender].inEncounter = false;
        emit CreatePlayer(msg.sender, _name, PLAYER_START_AC, PLAYER_START_HP, PLAYER_START_STR, PLAYER_START_ATK);
    }

    /**
    * @notice buyHealingPotion player can pay a fee to increase purchase
    * a healing potion.
    */
    function buyHealingPotion() external {
        require(!players[msg.sender].inEncounter, "cannot buy during encounter!");
        require(players[msg.sender].healingPotions < maxHealingPotions, "cannot carry any more");
        _payHealingPotionFees();
        players[msg.sender].healingPotions = players[msg.sender].healingPotions.add(1);
        emit BoughtHealingPotion(msg.sender, healingPotionFee);
    }

    /**
    * @notice drinkHealingPotion player can drink a healing potion during an encounter
    * @param _encounterId bytes32 id of encounter
    */
    function drinkHealingPotion(bytes32 _encounterId) external {
        require(encounters[_encounterId].player == msg.sender, "not your encounter");
        require(!encounters[_encounterId].isRolling, "roll currently in progress");
        require(players[msg.sender].healingPotions > 0, "no healing potion to use");
        uint256 healedHp = encounters[_encounterId].playerHp.add(healingPotionHp);

        require(healedHp <= players[msg.sender].hp, "cannot heal more than hp stat");

        players[msg.sender].healingPotions = players[msg.sender].healingPotions.sub(1);
        encounters[_encounterId].playerHp = healedHp;
        emit DrankHealingPotion(msg.sender, encounters[_encounterId].playerHp);
    }

    /**
    * @notice increaseArmourClass player can pay a fee to increase their AC
    * AC is their defence used when monsters attack, and can be increased
    * to a maximum of 25
    */
    function increaseArmourClass() external {
        require(!players[msg.sender].inEncounter, "cannot increase encounter!");
        require(players[msg.sender].ac < maxPlayerAc, "max AC reached");
        _payStatFees();
        players[msg.sender].ac = players[msg.sender].ac.add(1);
        emit StatIncreased(msg.sender, "AC", players[msg.sender].ac, statFee);
    }

    /**
    * @notice increaseHitPoints player can pay a fee to increase their HP
    * HP is their health and decreases when monsters attack. It can be increased
    * to a maximum of 100
    */
    function increaseHitPoints() external {
        require(!players[msg.sender].inEncounter, "cannot increase encounter!");
        require(players[msg.sender].hp < maxPlayerHp, "max HP reached");
        _payStatFees();
        players[msg.sender].hp = players[msg.sender].hp.add(5);
        emit StatIncreased(msg.sender, "HP", players[msg.sender].hp, statFee);
    }

    /**
    * @notice increaseStrengthModifier player can pay a fee to increase their STR
    * STR is added to their d20 attack roll and can be increased
    * to a maximum of 10. If d20 + STR >= Monster's AC, they hit.
    */
    function increaseStrengthModifier() external {
        require(!players[msg.sender].inEncounter, "cannot increase encounter!");
        require(players[msg.sender].str < maxPlayerStr, "max STR reached");
        _payStatFees();
        players[msg.sender].str = players[msg.sender].str.add(1);
        emit StatIncreased(msg.sender, "STR", players[msg.sender].str, statFee);
    }

    /**
    * @notice increaseAttackDice player can pay a fee to increase their ATK
    * ATK is the dice used to roll for damage and can be increased
    * to a maximum of 10.
    * 6 = d6
    * 8 = d8
    * 10 = d10
    * 12 = d12
    */
    function increaseAttackDice() external {
        require(!players[msg.sender].inEncounter, "cannot increase encounter!");
        require(players[msg.sender].atk < maxPlayerAtk, "max ATK reached");
        _payStatFees();
        players[msg.sender].atk = players[msg.sender].atk.add(2);
        emit StatIncreased(msg.sender, "ATK", players[msg.sender].atk, statFee);
    }

    /**
    * @notice increaseDamageModifier player can pay a fee to increase their DMG
    * is added to damage roll and can be increased
    * to a maximum of 10.
    */
    function increaseDamageModifier() external {
        require(!players[msg.sender].inEncounter, "cannot increase encounter!");
        require(players[msg.sender].dmg < maxPlayerDmg, "max DMG reached");
        _payStatFees();
        players[msg.sender].dmg = players[msg.sender].dmg.add(1);
        emit StatIncreased(msg.sender, "DMG", players[msg.sender].dmg, statFee);
    }

    /**
    * @notice pay required fees
    */
    function _payStatFees() internal {
        xFUND.transferFrom(msg.sender, address(this), statFee);
        withdrawableFees = withdrawableFees.add(statFee);
    }

    /**
    * @notice pay required fees
    */
    function _payHealingPotionFees() internal {
        xFUND.transferFrom(msg.sender, address(this), healingPotionFee);
        withdrawableFees = withdrawableFees.add(healingPotionFee);
    }

    /**
    * @notice newEncounter can be called by any wallet to begin a new encounter
    *
    * @param _monsterId uint256 id of the monster to fight
    * @return bytes32 fight id for use in rollForHit function and getting current encounter state
    */
    function newEncounter(uint256 _monsterId) external returns (bytes32) {
        require(players[msg.sender].ac > 0, "player does not exist");
        require(monsters[_monsterId].ac > 0, "monster does not exist");
        require(!players[msg.sender].inEncounter, "already in an encounter");
        bytes32 encounterId = keccak256(abi.encodePacked(msg.sender, _monsterId));
        encounters[encounterId].monsterId = _monsterId;
        encounters[encounterId].player = msg.sender;
        encounters[encounterId].playerHp = players[msg.sender].hp;
        encounters[encounterId].monsterHp = monsters[_monsterId].hp;
        encounters[encounterId].isRolling = false;
        players[msg.sender].inEncounter = true;
        emit StartEncounter(encounterId, msg.sender, _monsterId);
        return encounterId;
    }

    /**
    * @notice beginCombatRound called by a player to resolve a round of combat
    * for the selected encounter. Caller (msg.sender)
    * pays the xFUND fees for the randomness request.
    *
    * @param _encounterId bytes32 Id of the encounter
    * @param _seed uint256 seed for the randomness request. Gets mixed in with the blockhash of the block this Tx is in
    * @param _keyHash bytes32 key hash of the provider caller wants to fulfil the request
    * @param _fee uint256 required fee amount for the request
    */
    function beginCombatRound(bytes32 _encounterId, uint256 _seed, bytes32 _keyHash, uint256 _fee) external returns (bytes32 requestId) {
        require(encounters[_encounterId].player == msg.sender, "not your encounter");
        require(!encounters[_encounterId].isRolling, "roll currently in progress");
        // Note - caller must have increased xFUND allowance for this contract first.
        // Fee is transferred from msg.sender to this contract. The VORCoordinator.requestRandomness
        // function will then transfer from this contract to itself.
        // This contract's owner must have increased the VORCoordnator's allowance for this contract.
        xFUND.transferFrom(msg.sender, address(this), _fee);
        requestId = requestRandomness(_keyHash, _fee, _seed);
        emit CombatRoundInitialised(_encounterId, requestId);

        requestIdToEncounterId[requestId] = _encounterId;

        encounters[_encounterId].isRolling = true;
    }

    /**
     * @notice Callback function used by VOR Coordinator to return the random number
     * to this contract.
     * The returned randomness is used to resolve the combat round
     *
     * @param _requestId bytes32
     * @param _randomness The random result returned by the oracle
     */
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        bytes32 encounterId = requestIdToEncounterId[_requestId];
        require(encounters[encounterId].isRolling, "not currently rolling");

        (bool encounterOver, bool playerWon) = resolve(encounterId, _randomness);

        encounters[encounterId].isRolling = false;

        if(encounterOver) {
            players[encounters[encounterId].player].inEncounter = false;
            // emit EncounterOver event
            emit EncounterOver(encounterId, playerWon);
            // clean up
            delete requestIdToEncounterId[_requestId];
            delete encounters[encounterId];
        }
    }

    /**
     * @notice resolve takes the randomness result and resolves the combat
     * for the encounter.
     * The initial randomness value is split into 4 individual values,
     * representing the player's and monster's initial D20 roll to hit,
     * and their respective damage rolls.
     * The player's attack is always resolved first. If either the player's
     * or monster's HP for the encounter reaches 0, the encounter is over
     * and winner declared.
     * A tally of a player's wins/losses is kept in their Player struct.
     *
     * @param encounterId bytes32 id of the encounter being resolved
     * @param _randomness uint256 initial random value supplied by the VOR Oracle
     *
     * @return encounterOver bool whether or not the encounter is over
     * @return playerWon bool true if the player won, false if they were defeated
     */
    function resolve(bytes32 encounterId, uint256 _randomness) internal returns (bool, bool) {
        uint256 monsterId = encounters[encounterId].monsterId;
        address player = encounters[encounterId].player;

        // split _randomness into four individual values
        (uint64 playerHitRand, uint64 monsterHitRand, uint64 playerDmgRand, uint64 monsterDmgRand) = splitRoll(_randomness);

        resolvePlayer(encounterId, playerHitRand, playerDmgRand, player, monsterId);

        if(encounters[encounterId].monsterHp == 0) {
            players[player].won = players[player].won.add(1);
            return (true, true);
        }

        resolveMonster(encounterId, monsterHitRand, monsterDmgRand, player, monsterId);

        if(encounters[encounterId].playerHp == 0) {
            players[player].lost = players[player].lost.add(1);
            return (true, false);
        }

        return (false, false);
    }

    /**
     * @notice resolvePlayer resolves the Player's round of combat.
     * The playerHitRand value is used to roll the d20 to determine if the player
     * hit the monster.
     *
     * - A 20 always hits, and is a Critical Hit.
     * - A 1 always misses despite any modifiers.
     * - The player's STR modifier is added to the d20 roll
     * - if d20+STR >= Monster AC, the player hits and can cause damage to reduce the
     *   monster's HP.
     * - The damage is either a d6, d8 or d10, if the player has increased this
     * - the damage roll is doubled on Critical Hits
     * - The player's DMG modifier is finally added to the roll
     * - The monster's HP is reduced by this value
     * - if the monster's HP reaches zero, the encounter is over and the player wins
     *
     * @param encounterId bytes32 id of the encounter being resolved
     * @param playerHitRand uint64 random value used for d20 hit roll
     * @param playerDmgRand uint64 random value used for damage roll
     * @param player address of the player in this encounter
     * @param monsterId uint256 id of the monster in this encounter
     */
    function resolvePlayer(bytes32 encounterId, uint64 playerHitRand, uint64 playerDmgRand, address player, uint256 monsterId) internal {
        uint256 playerRoll = uint256(playerHitRand).mod(20).add(1);
        bool playerCrit = (playerRoll == 20);
        bool playerNaturalMiss = (playerRoll == 1);
        uint256 playerMod = playerRoll.add(players[player].str);
        bool playerHit = (playerMod >= monsters[monsterId].ac);

        uint256 playerDmg = uint256(playerDmgRand).mod(players[player].atk).add(1);

        if(playerCrit) {
            playerHit = true;
            playerDmg = playerDmg.mul(2);
        }

        if(playerHit && !playerNaturalMiss) {
            // add DMG modifer (note - done AFTER crit doubling)
            playerDmg = playerDmg.add(players[player].dmg);
            if(encounters[encounterId].monsterHp <= playerDmg) {
                encounters[encounterId].monsterHp = 0;
            } else {
                encounters[encounterId].monsterHp = encounters[encounterId].monsterHp.sub(playerDmg);
            }
        } else {
            playerDmg = 0;
        }

        uint256 monsterHp = encounters[encounterId].monsterHp;

        emit PlayerResult(encounterId, player, playerRoll, playerMod, playerHit, playerCrit, playerDmg, monsterHp );
    }

    /**
     * @notice resolveMonster resolves the Monster's round of combat.
     * The monsterHitRand value is used to roll the d20 to determine if the monster
     * hit the player.
     *
     * - A 20 always hits, and is a Critical Hit.
     * - A 1 always misses despite any modifiers.
     * - The monster's STR modifier is added to the d20 roll
     * - if d20+STR >= Player AC, the monster hits and can cause damage to reduce the
     *   player's HP.
     * - The damage is either a d6, d8 or d10
     * - the damage roll is doubled on Critical Hits
     * - The monster's DMG modifier is finally added to the roll
     * - The player's HP is reduced by this value
     * - if the player's HP reaches zero, the encounter is over and the player loses
     *
     * @param encounterId bytes32 id of the encounter being resolved
     * @param monsterHitRand uint64 random value used for d20 hit roll
     * @param monsterDmgRand uint64 random value used for damage roll
     * @param player address of the player in this encounter
     * @param monsterId uint256 id of the monster in this encounter
     */
    function resolveMonster(bytes32 encounterId, uint64 monsterHitRand, uint64 monsterDmgRand, address player, uint256 monsterId) internal {
        uint256 monsterRoll = uint256(monsterHitRand).mod(20).add(1);
        bool monsterCrit = (monsterRoll == 20);
        bool monsterNaturalMiss = (monsterRoll == 1);
        uint256 monsterMod = monsterRoll.add(monsters[monsterId].str);
        bool monsterHit = (monsterMod >= players[player].ac);
        uint256 monsterDmg = uint256(monsterDmgRand).mod(monsters[monsterId].atk).add(1);

        if(monsterCrit) {
            monsterHit = true;
            monsterDmg = monsterDmg.mul(2);
        }

        if(monsterHit && !monsterNaturalMiss) {
            // add DMG modifer (note - done AFTER crit doubling)
            monsterDmg = monsterDmg.add(monsters[monsterId].dmg);
            if(encounters[encounterId].playerHp <= monsterDmg) {
                encounters[encounterId].playerHp = 0;
            } else {
                encounters[encounterId].playerHp = encounters[encounterId].playerHp.sub(monsterDmg);
            }
        } else {
            monsterDmg = 0;
        }

        uint256 playerHp = encounters[encounterId].playerHp;

        emit MonsterResult(encounterId, monsterId, monsterRoll, monsterMod, monsterHit, monsterCrit, monsterDmg, playerHp);
    }

    /**
    * @notice splitRoll splits randomness into 4 values
    *
    * @param roll uint256 original randomness value returned by VOR Oracle
    * @return playerHitRand uint64 player's hit roll for d20
    * @return monsterHitRand uint64 monster's hit roll for d20
    * @return playerDmgRand uint64 player's ATK roll for damage
    * @return monsterDmgRand uint64 monster's ATK roll for damage
    */
    function splitRoll(uint256 roll) internal pure returns (uint64 playerHitRand, uint64 monsterHitRand, uint64 playerDmgRand, uint64 monsterDmgRand) {
        playerHitRand = uint64(roll >> 64*3);
        monsterHitRand = uint64(roll >> 64*2);
        playerDmgRand = uint64(roll >> 64*1);
        monsterDmgRand = uint64(roll >> 64*0);
    }

    /**
    * @notice unstickRoll allows contract owner to unstick a roll when a request is not fulfilled
    *
    * @param _encounterId bytes32 id of the encounter
    */
    function unstickRoll(bytes32 _encounterId) external onlyOwner {
        encounters[_encounterId].isRolling = false;
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
     * @notice withdrawStatFees Allows contract owner to withdraw any accumulated xFUND
     * statFees currently held by this contract
     */
    function withdrawStatFees(address to, uint256 value) external onlyOwner {
        require(withdrawableFees >= value, "not enough xfund");
        xFUND.transfer(to, value);
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
