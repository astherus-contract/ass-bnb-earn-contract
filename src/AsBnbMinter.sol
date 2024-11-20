// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./libraries/FullMath.sol";

import "./interfaces/IAsBnbMinter.sol";
import "./interfaces/IAsBNB.sol";
import "./interfaces/IYieldProxy.sol";
import { YieldProxy } from "./YieldProxy.sol";

contract AsBnbMinter is
  IAsBnbMinter,
  Initializable,
  AccessControlUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable
{
  using SafeERC20 for IERC20;
  using SafeERC20 for IAsBNB;
  // pause role
  bytes32 public constant PAUSER = keccak256("PAUSER");
  // manager role
  bytes32 public constant MANAGER = keccak256("MANAGER");
  // bot role
  bytes32 public constant BOT = keccak256("BOT");
  // denominator
  uint256 public constant DENOMINATOR = 10000;

  /* ======================
        State Variables
   ====================== */
  // original token address
  IERC20 public token;
  // asBnb address
  IAsBNB public asBnb;
  // total tokens deposited
  uint256 public totalTokens;
  // fee will be charged when LaunchPool rewards are compounded
  uint256 public feeRate;
  // rewards available to withdraw
  uint256 public feeAvailable;
  // yield proxy
  address public yieldProxy;
  // mint queue, pending mint requests
  // @notice when there is activity on going, the mint request will be added to this queue
  mapping(uint256 => TokenMintReq) public tokenMintReqQueue;
  // when the req at queueFront is processed, queueFront will be incremented
  uint256 public queueFront;
  // when there is a new mint req, queueRear will be incremented
  uint256 public queueRear;
  // minimum amount of token to mint
  uint256 public minMintAmount;

  /* ======================
          Modifiers
   ====================== */
  modifier onlyYieldProxy() {
    require(msg.sender == yieldProxy, "Caller is not yieldProxy");
    _;
  }

  /* ======================
            Events
   ====================== */
  event RewardsCompounded(address indexed sender, uint256 amountIn, uint256 lockAmount, uint256 fee);
  event FeeRateUpdated(address indexed sender, uint256 oldFeeRate, uint256 newFeeRate);
  event FeeWithdrawn(address indexed sender, address recipient, uint256 amount);
  event AddToken(address indexed asBnb, address indexed token);
  event TokenMintReqQueued(address indexed user, uint256 amountIn);
  event TokenMintReqProcessed(address indexed user, uint256 amountIn, uint256 amountToMint);
  event AsBnbMinted(address indexed user, uint256 amountIn, uint256 amountOut);
  event AsBnbBurned(address indexed user, uint256 amountToBurn, uint256 releaseTokenAmount);
  event MinMintAmountUpdated(address indexed sender, uint256 oldMinMintAmount, uint256 newMinMintAmount);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _admin - Address of the admin
   * @param _manager - Address of the manager
   * @param _pauser - Address of the pauser
   * @param _bot - Address of the bot
   * @param _token - Address of the token
   * @param _asBnb - Address of the asBnb
   * @param _yieldProxy - Address of the yieldProxy
   */
  function initialize(
    address _admin,
    address _manager,
    address _pauser,
    address _bot,
    address _token,
    address _asBnb,
    address _yieldProxy
  ) external initializer {
    require(_admin != address(0), "Invalid admin address");
    require(_manager != address(0), "Invalid manager address");
    require(_pauser != address(0), "Invalid pauser address");
    require(_bot != address(0), "Invalid bot address");
    require(_token != address(0), "Invalid token address");
    require(_asBnb != address(0), "Invalid AsBnb address");
    require(_yieldProxy != address(0), "Invalid yieldProxy address");

    __Pausable_init();
    __ReentrancyGuard_init();

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER, _manager);
    _grantRole(PAUSER, _pauser);
    _grantRole(BOT, _bot);

    feeRate = 0;
    token = IERC20(_token);
    asBnb = IAsBNB(_asBnb);
    yieldProxy = _yieldProxy;

    emit AddToken(_asBnb, _token);
  }

  /* ============================
          External Getters
  ============================ */
  /**
   * @dev convertToTokens  get token amount
   * @param asBnbAmt - amount of asBnb
   */
  function convertToTokens(uint256 asBnbAmt) public view returns (uint256) {
    uint256 totalSupply = asBnb.totalSupply();
    // Refer to ERC4626
    // https://docs.openzeppelin.com/contracts/4.x/erc4626#defending_with_a_virtual_offset
    return FullMath.mulDiv(asBnbAmt, totalTokens + 1, totalSupply + 1);
  }

  /**
   * @dev convertToAsBnb  get asBnb amount
   * @param tokens - amount of token
   */
  function convertToAsBnb(uint256 tokens) public view returns (uint256) {
    uint256 totalSupply = asBnb.totalSupply();
    // refer to ERC4626's standard
    return FullMath.mulDiv(tokens, totalSupply + 1, totalTokens + 1);
  }

  /* ============================
        External Functions
  ============================ */
  /**
   * @dev mint asBnb
   * @param amountIn - amount of token
   */
  function mintAsBnb(uint256 amountIn) external override whenNotPaused nonReentrant returns (uint256) {
    return _mint(amountIn);
  }

  /**
   * @dev burn asBnb - only yieldProxy can call this function
   * @param amountToBurn - amount of asBnb to burn
   */
  function burnAsBnb(uint256 amountToBurn) external override whenNotPaused nonReentrant returns (uint256) {
    require(amountToBurn > 0, "Invalid amount to burn");
    // transfer asBnb from user to this contract
    asBnb.safeTransferFrom(msg.sender, address(this), amountToBurn);
    // get amount of token can be released
    uint256 releaseTokenAmount = convertToTokens(amountToBurn);
    // record token amount decrement
    totalTokens -= releaseTokenAmount;
    // burn asBnb
    asBnb.burn(address(this), amountToBurn);
    // withdraw slisBNB
    IYieldProxy(yieldProxy).withdraw(releaseTokenAmount);
    // transfer token to user
    token.safeTransfer(msg.sender, releaseTokenAmount);

    emit AsBnbBurned(msg.sender, amountToBurn, releaseTokenAmount);
    return amountToBurn;
  }

  /**
   * @dev compoundRewards
   * @param amountIn - amount of token
   */
  function compoundRewards(uint256 amountIn) external override onlyYieldProxy whenNotPaused nonReentrant {
    require(amountIn > 0, "Invalid amount");
    // transfer token from YieldProxy
    token.safeTransferFrom(msg.sender, address(this), amountIn);

    // calculate fee and compound amount
    uint256 fee = (amountIn * feeRate) / DENOMINATOR;
    uint256 lockAmount = amountIn - fee;

    // add up fees and total deposited tokens
    feeAvailable += fee;
    totalTokens += lockAmount;

    // compound rewards
    token.safeIncreaseAllowance(yieldProxy, lockAmount);
    IYieldProxy(yieldProxy).deposit(lockAmount);

    emit RewardsCompounded(msg.sender, amountIn, lockAmount, fee);
  }

  /**
   * @dev process mint queue
   *      token has been transferred to YieldProxy before queued,
   *      the function will mint AsBNB to the defined recipient
   * @notice this can be executed if and only if there is no on going activity
   * @param batchSize - size of how much to process this time
   */
  function processMintQueue(uint256 batchSize) external whenNotPaused onlyRole(BOT) {
    require(!IYieldProxy(yieldProxy).activitiesOnGoing(), "Activity is on going");
    require(batchSize > 0, "Invalid batch size");
    require(queueFront != queueRear, "No pending mint request");
    for (uint256 i = 0; i < batchSize; ++i) {
      // stop when batchSize is greater than the remaining queue size
      // or reach to the end of the queue
      if (queueFront == queueRear) {
        break;
      }
      // get token mint req. from the queue
      TokenMintReq memory req = tokenMintReqQueue[queueFront];
      uint256 amountToMint = convertToAsBnb(req.amountIn);
      // record token amount increment
      totalTokens += req.amountIn;
      // mint asBnb
      asBnb.mint(req.user, amountToMint);
      // remove request from the queue
      delete tokenMintReqQueue[queueFront];
      // increment queueFront
      ++queueFront;
      // emit event
      emit TokenMintReqProcessed(req.user, req.amountIn, amountToMint);
    }
  }

  /* ============================
          Admin Functions
  ============================ */
  /**
   * @dev Flips the pause state
   */
  function unpause() external onlyRole(MANAGER) {
    _unpause();
  }

  /**
   * @dev pause the contract
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /**
   * @dev set fee rate
   * @param _feeRate - fee rate which can be zero
   */
  function setFeeRate(uint256 _feeRate) external onlyRole(MANAGER) {
    require(_feeRate >= 0 && _feeRate <= DENOMINATOR, "Invalid fee rate");
    require(_feeRate != feeRate, "_fee rate can't equals to old fee rate");

    uint256 oldFeeRate = feeRate;
    // update new fee rate
    feeRate = _feeRate;

    emit FeeRateUpdated(msg.sender, oldFeeRate, _feeRate);
  }

  /**
   * @dev set min. amount to mint
   * @param _minMintAmount - minimum amount of token to mint
   */
  function setMinMintAmount(uint256 _minMintAmount) external onlyRole(MANAGER) {
    require(_minMintAmount > 0 && _minMintAmount != minMintAmount, "Invalid minMintAmount");
    uint256 oldMinMintAmount = minMintAmount;
    minMintAmount = _minMintAmount;
    emit MinMintAmountUpdated(msg.sender, oldMinMintAmount, _minMintAmount);
  }

  /**
   * @dev withdraw collected fee from launchpool profits
   * @param recipient - Address of the recipient
   * @param withdrawAmount - amount of token
   */
  function withdrawFee(address recipient, uint256 withdrawAmount) external nonReentrant onlyRole(MANAGER) {
    require(recipient != address(0), "Invalid recipient address");
    require(withdrawAmount > 0 && withdrawAmount <= feeAvailable, "Invalid withdrawAmount");

    feeAvailable -= withdrawAmount;
    token.safeTransfer(recipient, withdrawAmount);

    emit FeeWithdrawn(msg.sender, recipient, withdrawAmount);
  }

  /* ============================
        Internal Functions
  ============================ */
  function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

  /**
   * @dev mint asBnb
   * @param amountIn - amount of token
   */
  function _mint(uint256 amountIn) private returns (uint256) {
    require(amountIn >= minMintAmount, "amount is less than minMintAmount");
    // transfer token to YieldProxy
    token.transferFrom(msg.sender, address(this), amountIn);
    token.safeIncreaseAllowance(yieldProxy, amountIn);
    IYieldProxy(yieldProxy).deposit(amountIn);

    // queue mint request if there is on going activity
    if (IYieldProxy(yieldProxy).activitiesOnGoing()) {
      // set queueFront tokenMintReq
      tokenMintReqQueue[queueRear] = TokenMintReq(msg.sender, amountIn);
      // increment queueRear
      ++queueRear;
      // emit event
      emit TokenMintReqQueued(msg.sender, amountIn);
      return 0;
    } else {
      // calculate amount to mint
      uint256 amountToMint = convertToAsBnb(amountIn);
      // record token amount increment
      totalTokens += amountIn;
      // mint asBnb
      asBnb.mint(msg.sender, amountToMint);
      // emit event
      emit AsBnbMinted(msg.sender, amountIn, amountToMint);
      return amountToMint;
    }
  }
}
