// SPDX-License-Identifier: MIT
pragma solidity =0.8.7;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

    struct BackstopOrder {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        address precisionUser;
        uint256 deadline;
        uint256 nonce;
    }

    struct PrecisionOrder {
        uint256 amountIn;
        uint256 amountOut;
        uint256 deadline;
    }

contract SonOfASwap {
    uint256 public status;
    address private owner;
    mapping(address => uint256) public nonces;

    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    string private constant EIP712_DOMAIN =
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    string private constant SWAPORDER =
    "SwapOrder(address router,uint256 amountIn,uint256 amountOut,string tradeType,address recipient,address[] path,uint deadline,uint256 sqrtPriceLimitX96,uint256 fee,uint256 nonce)";
    string private constant BACKSTOPORDER =
    "BackstopOrder((address tokenIn,address tokenOut,uint256 amountIn,uint256 amountOut,address precisionUser,uint256 deadline,uint256 nonce)";
    string private constant PRECISIONORDER =
    "PrecisionOrder((uint256 amountIn,uint256 amountOut,uint256 deadline)";


    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
    keccak256(abi.encodePacked(EIP712_DOMAIN));
    bytes32 private constant SWAPORDER_TYPEHASH =
    keccak256(abi.encodePacked(SWAPORDER));
    bytes32 private constant BACKSTOPORDER_TYPEHASH =
    keccak256(abi.encodePacked(BACKSTOPORDER));
    bytes32 private constant PRECISIONORDER_TYPEHASH =
    keccak256(abi.encodePacked(BACKSTOPORDER));

    bytes32 private DOMAIN_SEPARATOR;

    function getChainID() internal view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    constructor() {
        owner = msg.sender;
        status = 0;
        DOMAIN_SEPARATOR = hash(
            EIP712Domain({
        name: "SonOfASwap",
        version: "1",
        chainId: getChainID(),
        verifyingContract: address(this)
        })
        );
    }

    receive() external payable {}

    function settle(BackstopOrder calldata backstopOrder,
        uint8 v,
        bytes32 r,
        bytes32 s,

        PrecisionOrder calldata precisionOrder,
        uint8 precisionV,
        bytes32 precisionR,
        bytes32 precisionS) external
    {
        address executionUser = recoverBackstopOrder(backstopOrder, v, r, s);

        require (verifyPrecisionOrder(precisionOrder, backstopOrder.precisionUser, precisionV, precisionR, precisionS), "Precision signature does not match" );
        require(precisionOrder.amountIn >= backstopOrder.amountIn && precisionOrder.amountOut <= backstopOrder.amountOut, "Precision order has lower price than backstop");
        require(backstopOrder.deadline < block.timestamp && precisionOrder.deadline < block.timestamp, "Deadline exceeded");

        backstopOrder.tokenIn.transferFrom(msg.sender, executionUser, precisionOrder.amountIn);
        backstopOrder.tokenOut.transferFrom(executionUser, msg.sender, precisionOrder.amountOut);
    }

    function hash(EIP712Domain memory eip712Domain)
    internal
    pure
    returns (bytes32)
    {
        return
        keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(eip712Domain.name)),
                keccak256(bytes(eip712Domain.version)),
                eip712Domain.chainId,
                eip712Domain.verifyingContract
            )
        );
    }

    function hashBackstop(BackstopOrder memory order) internal pure returns (bytes32) {
        return
        keccak256(
            abi.encode(
                BACKSTOPORDER_TYPEHASH,
                order.tokenIn,
                order.tokenOut,
                order.amountIn,
                order.amountOut,
                order.precisionUser,
                order.deadline,
                order.nonce
            )
        );
    }

    function hashPrecision(PrecisionOrder memory order) internal pure returns (bytes32) {
        return
        keccak256(
            abi.encode(
                PRECISIONORDER_TYPEHASH,
                order.amountIn,
                order.amountOut,
                order.deadline
            )
        );
    }


    function verifyPrecisionOrder(
        PrecisionOrder memory order,
        address precisionUser,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (bool) {
        // Note: we need to use `encodePacked` here instead of `encode`.
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashPrecision(order))
        );
        address recovered = ecrecover(digest, v, r, s);
        return recovered == precisionUser;
    }

    function recoverBackstopOrder(
        BackstopOrder memory backstopOrder,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view returns (address) {
        // Note: we need to use `encodePacked` here instead of `encode`.
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashBackstop(backstopOrder))
        );
        return ecrecover(digest, v, r, s);
    }


    function stringsEqual(string memory a, string memory b)
    internal
    pure
    returns (bool)
    {
        return (keccak256(abi.encodePacked((a))) ==
        keccak256(abi.encodePacked((b))));
    }

    /**
    Encodes multihop V3 path.
    https://docs.uniswap.org/protocol/guides/swaps/multihop-swaps
    */
    function encodeMultihopPath(address[] memory path, uint24 fee)
    internal
    pure
    returns (bytes memory)
    {
        bytes memory encodedPath;
        for (uint256 i = 0; i < path.length; i++) {
            encodedPath = abi.encodePacked(encodedPath, path[i]);
            if (i < path.length - 1) {
                // path = abi.encodePacked(path, fees[i]); // TODO <<
                encodedPath = abi.encodePacked(encodedPath, fee);
            }
        }
        return encodedPath;
    }

    // liquidate assets from this contract (for testing purposes only)
    function liquidate(address tokenAddress) public {
        require(msg.sender == owner);
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
    }
}
