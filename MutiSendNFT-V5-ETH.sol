// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Not the contract owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Invalid address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status;

    constructor() {
        _status = 1;
    }

    modifier nonReentrant() {
        require(_status != 2, "ReentrancyGuard: reentrant call");
        _status = 2;
        _;
        _status = 1;
    }
}

contract NFTMultiSender is Ownable, ReentrancyGuard {
    event NFTTransferred(address indexed nftAddress, address indexed from, address indexed to, uint256 tokenId);
    event NFTsSent(address indexed nftAddress, address sender, uint256 count, uint256 totalFee);
    event BatchWithdraw(address indexed nftAddress, uint256 count);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event ETHWithdrawn(address indexed to, uint256 amount);

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    uint256 public feePerItem = 0.00003 ether;
    uint256 public constant MAX_BATCH_SIZE = 1000;

    constructor() {}

    function setFeePerItem(uint256 _fee) external onlyOwner {
        emit FeeUpdated(feePerItem, _fee);
        feePerItem = _fee;
    }

    function calculateTotalFee(uint256 itemCount) public view returns (uint256) {
        return feePerItem * itemCount;
    }

    function multiSendERC721(
        address nftAddress,
        address[] calldata recipients,
        uint256[] calldata tokenIds
    ) external payable nonReentrant {
        require(recipients.length == tokenIds.length, "Length mismatch");
        require(recipients.length > 0 && recipients.length <= MAX_BATCH_SIZE, "Batch size must be 1 to 500");
        require(_isERC721(nftAddress), "Not an ERC721 contract");

        IERC721 token = IERC721(nftAddress);
        uint256 totalFee = calculateTotalFee(recipients.length);
        require(msg.value >= totalFee, "Insufficient ETH for fee");

        for (uint i = 0; i < recipients.length; ) {
            address tokenOwner = token.ownerOf(tokenIds[i]);
            require(
                msg.sender == tokenOwner || token.getApproved(tokenIds[i]) == address(this),
                "Not approved or not owner"
            );

            token.safeTransferFrom(tokenOwner, recipients[i], tokenIds[i]);
            emit NFTTransferred(nftAddress, tokenOwner, recipients[i], tokenIds[i]);

            unchecked {
                ++i;
            }
        }

        emit NFTsSent(nftAddress, msg.sender, recipients.length, totalFee);
    }

    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        payable(owner()).transfer(balance);
        emit ETHWithdrawn(owner(), balance);
    }

    function withdrawERC721(address nftAddress, uint256 tokenId) external onlyOwner {
        IERC721(nftAddress).safeTransferFrom(address(this), owner(), tokenId);
    }

    function batchWithdrawERC721(address nftAddress, uint256[] calldata tokenIds) external onlyOwner {
        IERC721 token = IERC721(nftAddress);

        for (uint i = 0; i < tokenIds.length; ) {
            token.safeTransferFrom(address(this), owner(), tokenIds[i]);
            unchecked {
                ++i;
            }
        }

        emit BatchWithdraw(nftAddress, tokenIds.length);
    }

    function _isERC721(address nftAddress) internal view returns (bool) {
        try IERC165(nftAddress).supportsInterface(INTERFACE_ID_ERC721) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }
}

