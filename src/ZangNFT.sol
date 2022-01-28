// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {Base64} from "./MetadataUtils.sol";
import "../node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "./ERC2981PerTokenRoyalties.sol";
import {StringUtils} from "./StringUtils.sol";

contract ZangNFT is
    ERC1155Supply,
    ERC2981PerTokenRoyalties
{
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    mapping(uint256 => string) private _textURIs;

    mapping(uint256 => string) private _names;

    mapping(uint256 => string) private _descriptions;

    mapping(uint256 => address) private _authors;

    string public name;
    string public symbol;

    constructor(string memory name_, string memory symbol_) ERC1155("") {
        name = name_;
        symbol = symbol_;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC2981PerTokenRoyalties)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function lastTokenId() public view returns (uint256) {
        return _tokenIds.current();
    }

    function nameOf(uint256 tokenId) public view returns (string memory) {
        require(exists(tokenId), "ZangNFT: name query for nonexistent token");
        return _names[tokenId];
    }

    function descriptionOf(uint256 tokenId) public view returns (string memory) {
        require(exists(tokenId), "ZangNFT: description query for nonexistent token");
        return _descriptions[tokenId];
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        require(exists(tokenId), "ZangNFT: uri query for nonexistent token");
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{ "name": "',
                        StringUtils.insertBeforeAsciiString(_names[tokenId], '"', '\\'),
                        '", ',
                        '"description" : ',
                        '"',
                        StringUtils.insertBeforeAsciiString(_descriptions[tokenId], '"', '\\'),
                        '", ',
                        //'"image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '", '
                        '"textURI" : ',
                        '"',
                        textURI(tokenId),
                        '"',
                        "}"
                    )
                )
            )
        );
        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }

    function authorOf(uint256 _tokenId) external view returns (address) {
        address author = _authors[_tokenId];
        require(
            author != address(0),
            "ZangNFT: author query for nonexistent token"
        );
        return author;
    }

    function mint(
        string memory textURI_,
        string memory name_,
        string memory description_,
        uint256 amount_,
        uint256 royaltyPercentage_, //NB: two decimals, so 10% is 1000
        address royaltyRecipient_,
        bytes memory data_
    ) external returns (uint256) {
        _tokenIds.increment();

        uint256 newTokenId = _tokenIds.current();
        _setTextURI(newTokenId, textURI_);
        _names[newTokenId] = name_;
        _descriptions[newTokenId] = description_;
        _authors[newTokenId] = msg.sender;
        _setTokenRoyalty(newTokenId, royaltyRecipient_, royaltyPercentage_);

        _mint(msg.sender, newTokenId, amount_, data_);

        return newTokenId;
    }

    function _setTextURI(uint256 _tokenId, string memory _textURI) internal {
        _textURIs[_tokenId] = _textURI;
    }

    function textURI(uint256 tokenId)
        public
        view
        virtual
        returns (string memory)
    {
        require(
            exists(tokenId),
            "ZangNFT: textURI query for nonexistent token"
        );
        return _textURIs[tokenId];
    }

    function burn(address _from, uint256 _tokenId, uint256 _amount) external {
        require(
            _from == msg.sender || isApprovedForAll(_from, msg.sender),
            "ZangNFT: caller is not owner nor approved"
        );
        
        _burn(_from, _tokenId, _amount);

        if(totalSupply(_tokenId) == 0) {
            delete _textURIs[_tokenId];
            delete _names[_tokenId];
            delete _descriptions[_tokenId];
            delete _authors[_tokenId];
        }
    }
}