// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface of the SPACE ID Agent ID registry
///         (BNB Chain: 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F).
///         Agent ID is a non-transferable ERC-721 ("name.ai"); holding one
///         is proven with balanceOf(address) > 0, exactly as documented in
///         the Binance Agent ID Hackathon announcement.
interface IAgentIDRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentGate — the Agent ID holders' clubhouse on BNB Chain
/// @notice AgentGate turns an Agent ID into a working key:
///         1. Holders claim a soulbound badge NFT (one per address).
///         2. Badge holders check in once per UTC day and build streaks.
///         3. Claims can name an inviter (another holder), so the club
///            grows holder-to-holder.
///         The contract is deliberately permissionless and ownerless:
///         no admin keys, no mint switch, no pause, no funds held, no
///         function that can move anyone's assets. The Agent ID check is
///         performed on every claim and every check-in.
contract AgentGate {
    // ------------------------------------------------------------------
    // Badge identity (ERC-721 metadata)
    // ------------------------------------------------------------------
    string public constant name = "AgentGate Badge";
    string public constant symbol = "AGATE";

    /// @notice The Agent ID registry this gate reads. Immutable.
    IAgentIDRegistry public immutable agentIdRegistry;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    uint256 public totalBadges;
    uint256 public totalCheckIns;

    mapping(uint256 => address) private _ownerOfToken;
    mapping(address => uint256) private _badgeOf; // tokenId, 0 = no badge
    mapping(address => uint256) public claimedAt;
    mapping(address => address) public inviterOf;

    struct Activity {
        uint32 streak;     // current consecutive-day streak
        uint32 bestStreak; // best streak ever
        uint32 checkIns;   // lifetime check-ins
        uint32 lastDay;    // last check-in day (unix days)
    }
    mapping(address => Activity) private _activity;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event BadgeClaimed(address indexed holder, uint256 indexed tokenId, address indexed inviter);
    event CheckedIn(address indexed holder, uint256 indexed day, uint32 streak, uint32 totalCheckIns);

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------
    error NotAgentIdHolder();
    error BadgeAlreadyClaimed();
    error NoBadge();
    error AlreadyCheckedInToday();
    error SelfInvite();
    error Soulbound();
    error NonexistentToken();
    error ZeroAddress();

    constructor(address registry_) {
        if (registry_ == address(0)) revert ZeroAddress();
        agentIdRegistry = IAgentIDRegistry(registry_);
    }

    // ------------------------------------------------------------------
    // Core: Agent ID gate
    // ------------------------------------------------------------------
    /// @notice True when `user` currently holds an Agent ID.
    function isAgentIdHolder(address user) public view returns (bool) {
        return agentIdRegistry.balanceOf(user) > 0;
    }

    // ------------------------------------------------------------------
    // Core: claim the soulbound badge (one per Agent ID holder address)
    // ------------------------------------------------------------------
    /// @param inviter Another holder who invited you, or address(0).
    ///        Purely a public attribution record; it moves no assets and
    ///        grants the inviter nothing but a counter.
    function claimBadge(address inviter) external {
        if (!isAgentIdHolder(msg.sender)) revert NotAgentIdHolder();
        if (_badgeOf[msg.sender] != 0) revert BadgeAlreadyClaimed();
        if (inviter == msg.sender) revert SelfInvite();

        uint256 tokenId = ++totalBadges;
        _badgeOf[msg.sender] = tokenId;
        _ownerOfToken[tokenId] = msg.sender;
        claimedAt[msg.sender] = block.timestamp;
        inviterOf[msg.sender] = inviter;

        emit Transfer(address(0), msg.sender, tokenId);
        emit BadgeClaimed(msg.sender, tokenId, inviter);
    }

    // ------------------------------------------------------------------
    // Core: daily check-in (builds streaks; one per UTC day)
    // ------------------------------------------------------------------
    function checkIn() external {
        if (_badgeOf[msg.sender] == 0) revert NoBadge();
        // The gate is live, not a one-time check: a check-in re-verifies
        // that the caller still holds an Agent ID.
        if (!isAgentIdHolder(msg.sender)) revert NotAgentIdHolder();

        uint256 today = block.timestamp / 1 days;
        Activity storage a = _activity[msg.sender];
        if (a.lastDay == today) revert AlreadyCheckedInToday();

        if (a.lastDay == today - 1) {
            a.streak += 1;
        } else {
            a.streak = 1;
        }
        if (a.streak > a.bestStreak) a.bestStreak = a.streak;
        a.checkIns += 1;
        a.lastDay = uint32(today);
        totalCheckIns += 1;

        emit CheckedIn(msg.sender, today, a.streak, a.checkIns);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------
    function badgeOf(address user) external view returns (uint256) {
        return _badgeOf[user];
    }

    function profileOf(address user)
        external
        view
        returns (
            bool hasBadge,
            uint256 tokenId,
            uint32 streak,
            uint32 bestStreak,
            uint32 checkIns,
            uint32 lastDay,
            address inviter,
            uint256 claimedAtTs
        )
    {
        Activity storage a = _activity[user];
        return (
            _badgeOf[user] != 0,
            _badgeOf[user],
            a.streak,
            a.bestStreak,
            a.checkIns,
            a.lastDay,
            inviterOf[user],
            claimedAt[user]
        );
    }

    function stats() external view returns (uint256 badges, uint256 checkIns) {
        return (totalBadges, totalCheckIns);
    }

    // ------------------------------------------------------------------
    // ERC-721 surface (soulbound: every transfer/approval path reverts)
    // ------------------------------------------------------------------
    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _badgeOf[owner] == 0 ? 0 : 1;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _ownerOfToken[tokenId];
        if (owner == address(0)) revert NonexistentToken();
        return owner;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        address owner = _ownerOfToken[tokenId];
        if (owner == address(0)) revert NonexistentToken();
        Activity storage a = _activity[owner];
        string memory json = string(
            abi.encodePacked(
                '{"name":"AgentGate Badge #',
                _toString(tokenId),
                '","description":"Soulbound badge of the AgentGate clubhouse. '
                'Only Agent ID (name.ai) holders can claim it. The badge levels '
                'up with daily check-in streaks.","attributes":[',
                '{"trait_type":"Check-in streak","value":',
                _toString(a.streak),
                '},{"trait_type":"Best streak","value":',
                _toString(a.bestStreak),
                '},{"trait_type":"Total check-ins","value":',
                _toString(a.checkIns),
                "}]}"
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(json))));
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    function approve(address, uint256) external pure {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) external pure {
        revert Soulbound();
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_ownerOfToken[tokenId] == address(0)) revert NonexistentToken();
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert Soulbound();
    }

    // ------------------------------------------------------------------
    // Small string helpers (kept dependency-free on purpose)
    // ------------------------------------------------------------------
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _base64(bytes memory data) internal pure returns (string memory) {
        bytes memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        if (data.length == 0) return "";
        uint256 encodedLength = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLength + 32);
        uint256 i;
        uint256 j;
        for (i = 0; i < data.length; i += 3) {
            uint256 a = uint8(data[i]);
            uint256 b = i + 1 < data.length ? uint8(data[i + 1]) : 0;
            uint256 c = i + 2 < data.length ? uint8(data[i + 2]) : 0;
            uint256 n = (a << 16) | (b << 8) | c;
            result[j++] = table[(n >> 18) & 63];
            result[j++] = table[(n >> 12) & 63];
            result[j++] = i + 1 < data.length ? table[(n >> 6) & 63] : bytes1("=");
            result[j++] = i + 2 < data.length ? table[n & 63] : bytes1("=");
        }
        // trim the scratch padding
        bytes memory out = new bytes(j);
        for (i = 0; i < j; i++) {
            out[i] = result[i];
        }
        return string(out);
    }
}
