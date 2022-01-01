// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import "hardhat/console.sol";

/// [MIT License]
library StringUtils {
    function utfLength(bytes1 b) private pure returns (uint8) {
        if (b < 0x80) {
            return 1;
        } else if(b < 0xE0) {
            return 2;
        } else if(b < 0xF0) {
            return 3;
        } else if(b < 0xF8) {
            return 4;
        } else if(b < 0xFC) {
            return 5;
        } else {
            return 6;
        }
    }

    function firstN(bytes memory arr, uint256 n) internal pure returns (bytes memory) {
        bytes memory newArray = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            newArray[i] = arr[i];
        }

        return newArray;
    }

    function insertAsciiBefore(bytes memory str, bytes1 target, bytes1 insert) internal pure returns (bytes memory) {
        require(utfLength(target) == 1, "StringUtils: target must be ASCII");
        require(utfLength(insert) == 1, "StringUtils: insert must be ASCII");

        bytes memory newString = new bytes(str.length * 2);
        uint256 from = 0;
        uint256 to = 0;
        while (from < str.length) {
            // console.log("Test %s %s", from, uint8(str[from]));
            // console.log("Index %s, char %s", from, copy);
            bytes1 b = str[from];
            uint8 bLength = utfLength(b);

            if (bLength == 1 && b == target) {
                // ASCII character that matches our target
                newString[to] = insert;
                to++;
            }

            for (uint8 j = 0; j < bLength; j++) {
                newString[to + j] = str[from + j];
            }

            to += bLength;
            from += bLength;
        }

        return firstN(newString, to);
    }

    function insertAsciiBeforeString(string memory str, bytes1 target, bytes1 insert) internal pure returns (string memory) {
        return string(insertAsciiBefore(bytes(str), target, insert));
    }
}