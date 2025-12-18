// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title DMDToken - Extreme Deflationary Digital Asset
/// @dev Dual minter: MintDistributor (emissions) + VestingContract (team allocation)
/// @dev Public burn, 18M max supply, fully decentralized
contract DMDToken {
    error Unauthorized();
    error ExceedsMaxSupply();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidRecipient();

    string public constant name = "DMD Protocol";
    string public constant symbol = "DMD";
    uint8 public constant decimals = 18;
    uint256 public constant MAX_SUPPLY = 18_000_000e18;

    address public immutable mintDistributor;
    address public immutable vestingContract;
    uint256 public totalMinted;
    uint256 public totalBurned;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(address _mintDistributor, address _vestingContract) {
        if (_mintDistributor == address(0) || _vestingContract == address(0)) revert InvalidRecipient();
        mintDistributor = _mintDistributor;
        vestingContract = _vestingContract;
    }

    function totalSupply() public view returns (uint256) { return totalMinted - totalBurned; }

    function mint(address to, uint256 amount) external {
        if (msg.sender != mintDistributor && msg.sender != vestingContract) revert Unauthorized();
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (totalMinted + amount > MAX_SUPPLY) revert ExceedsMaxSupply();

        totalMinted += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        totalBurned += amount;
        emit Transfer(msg.sender, address(0), amount);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        if (to == address(0)) revert InvalidRecipient();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (to == address(0)) revert InvalidRecipient();

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientBalance();
            allowance[from][msg.sender] = allowed - amount;
        }

        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
