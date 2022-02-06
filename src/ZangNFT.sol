// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {Base64} from "./MetadataUtils.sol";
import "../node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "../node_modules/@openzeppelin/contracts/utils/Strings.sol";
import "./ERC2981.sol";
import {StringUtils} from "./StringUtils.sol";
import "./ZangNFTCommissions.sol";

contract ZangNFT is
    ERC1155Supply,
    ERC2981,
    ZangNFTCommissions
{
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    mapping(uint256 => string) private _textURIs;

    mapping(uint256 => string) private _names;

    mapping(uint256 => string) private _descriptions;

    mapping(uint256 => address) private _authors;

    string public name;
    string public symbol;
    string public description;
    string public imageURI;
    string public externalLink;

    constructor(string memory _name, string memory _symbol, string memory _description, string memory _imageURI, string memory _externalLink, address _zangCommissionAccount) ERC1155("") ZangNFTCommissions(_zangCommissionAccount) {
        name = _name;
        symbol = _symbol;
        description = _description;
        imageURI = _imageURI;
        externalLink = _externalLink;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function contractURI() public view returns (string memory) {
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{',
                        '"name": "',
                        StringUtils.insertBeforeAsciiString(name, '"', '\\'),
                        '", ',
                        '"description": ',
                        '"',
                        StringUtils.insertBeforeAsciiString(description, '"', '\\'),
                        '", ',
                        '"image": "', imageURI, '", '
                        '"external_link": "', externalLink, '", '
                        '"seller_fee_basis_points" : ', Strings.toString(platformFeePercentage), ', '
                        '"fee_recipient": "', Strings.toHexString(uint256(uint160(zangCommissionAccount)), 20), '"'
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
                        '"text_uri" : ',
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

    function authorOf(uint256 _tokenId) public view returns (address) {
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
        uint96 royaltyNumerator_, //NB: two decimals, so 10% is 1000
        address royaltyRecipient_,
        bytes memory data_
    ) external returns (uint256) {
        _tokenIds.increment();

        uint256 newTokenId = _tokenIds.current();
        _setTextURI(newTokenId, textURI_);
        _names[newTokenId] = name_;
        _descriptions[newTokenId] = description_;
        _authors[newTokenId] = msg.sender;
        _setTokenRoyalty(newTokenId, royaltyRecipient_, royaltyNumerator_);

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

    function decreaseRoyaltyNumerator(uint256 _tokenId, uint96 _lowerValue) external {
        require(
            exists(_tokenId),
            "ZangNFT: decreasing royalty numerator for nonexistent token"
        ); // Opt.
        require(msg.sender == authorOf(_tokenId), "ZangNFT: caller is not author");

        _decreaseRoyaltyNumerator(_tokenId, _lowerValue);
    }

    function royaltyNumerator(uint256 _tokenId) external view returns (uint96) {
        require(
            exists(_tokenId),
            "ZangNFT: royalty info query for nonexistent token"
        ); // Opt.
        return _royaltyNumerator(_tokenId);
    }

    function royaltyDenominator() external pure returns (uint96) {
        return _feeDenominator();
    }
}