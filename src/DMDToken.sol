// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title DMDToken
 * @notice Extreme Deflationary Digital Asset - Core Token Contract
 * @dev Mint-only via authorized distributor, public burn, immutable supply cap
 */
contract DMDToken {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error ExceedsMaxSupply();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidRecipient();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    string public constant name = "DMD Protocol";
    string public constant symbol = "DMD";
    uint8 public constant decimals = 18;
    
    uint256 public constant MAX_SUPPLY = 18_000_000e18;

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    address public immutable mintDistributor;

    uint256 public totalMinted;
    uint256 public totalBurned;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _mintDistributor) {
        if (_mintDistributor == address(0)) revert InvalidRecipient();
        mintDistributor = _mintDistributor;
    }

    /*//////////////////////////////////////////////////////////////
                          SUPPLY VIEWS
    //////////////////////////////////////////////////////////////*/

    function totalSupply() public view returns (uint256) {
        return totalMinted - totalBurned;
    }

    function circulatingSupply() public view returns (uint256) {
        return totalSupply();
    }

    /*//////////////////////////////////////////////////////////////
                          MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external {
        if (msg.sender != mintDistributor) revert Unauthorized();
        if (to == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        
        uint256 newTotalMinted = totalMinted + amount;
        if (newTotalMinted > MAX_SUPPLY) revert ExceedsMaxSupply();

        totalMinted = newTotalMinted;
        balanceOf[to] += amount;

        emit Minted(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          BURNING LOGIC
    //////////////////////////////////////////////////////////////*/

    function burn(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        totalBurned += amount;

        emit Burned(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

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

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
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