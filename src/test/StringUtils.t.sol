// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;
import "ds-test/test.sol";

import "../ZangNFT.sol";
import "../Marketplace.sol";
import {StringUtils} from "../StringUtils.sol";

interface Hevm {
    function prank(address) external;
    function expectRevert(bytes calldata) external;
    function deal(address, uint256) external;
    function startPrank(address) external;
    function stopPrank() external;
}

contract StringUtilsWrapper {
    function wrappedInsertBeforeAscii(bytes memory str, bytes1 target, bytes1 insert) public pure returns (bytes memory) {
        return StringUtils.insertBeforeAscii(str, target, insert);
    }
}

contract StringUtilsTest is DSTest {
    Hevm constant hevm = Hevm(HEVM_ADDRESS);
    StringUtilsWrapper wrapper = new StringUtilsWrapper();
    function setUp() public {
    }

    // 1: a, b, +, -, *, spazio, @
    function test_utf_length_with_one_byte_chars() public {
        uint n = StringUtils.utfLength("a");
        assertEq(n, 1);

        n = StringUtils.utfLength("b");
        assertEq(n, 1);

        n = StringUtils.utfLength("+");
        assertEq(n, 1);

        n = StringUtils.utfLength("-");
        assertEq(n, 1);

        n = StringUtils.utfLength("*");
        assertEq(n, 1);

        n = StringUtils.utfLength(" ");
        assertEq(n, 1);

        n = StringUtils.utfLength("@");
        assertEq(n, 1);
    }

    function first_byte(string memory s) public pure returns (bytes1) {
        return bytes(s)[0];
    }

    // 2: ì, ò, ç, §, è, ù, Ǝ, Ɵ, ©, ¼, Ã, Ç, ö, ÷
    function test_utf_length_with_two_bytes_chars() public {
        uint n = StringUtils.utfLength(first_byte(unicode"ì"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"ò"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"ç"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"§"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"è"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"ù"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"Ǝ"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"Ɵ"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"©"));
        assertEq(n, 2);
        
        n = StringUtils.utfLength(first_byte(unicode"¼"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"Ã"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"Ç"));
        assertEq(n, 2);
        
        n = StringUtils.utfLength(first_byte(unicode"ö"));
        assertEq(n, 2);

        n = StringUtils.utfLength(first_byte(unicode"÷"));
        assertEq(n, 2);
    }

    // 3: ⺷, ㋕, 㑥, 㪶, 東, 方, ㄲ, ㅉ
    function test_utf_length_with_three_bytes_chars() public {
        uint n = StringUtils.utfLength(first_byte(unicode"⺷"));
        assertEq(n, 3);

        n = StringUtils.utfLength(first_byte(unicode"㋕"));
        assertEq(n, 3);

        n = StringUtils.utfLength(first_byte(unicode"㑥"));
        assertEq(n, 3);

        n = StringUtils.utfLength(first_byte(unicode"㪶"));
        assertEq(n, 3);

        n = StringUtils.utfLength(first_byte(unicode"東"));
        assertEq(n, 3);

        n = StringUtils.utfLength(first_byte(unicode"方"));
        assertEq(n, 3);

        n = StringUtils.utfLength(first_byte(unicode"ㄲ"));
        assertEq(n, 3);

        n = StringUtils.utfLength(first_byte(unicode"ㅉ"));
        assertEq(n, 3);
    }

    // 4: 𒀁, 𓃘, 𓇼, 𝅘𝅥𝅰, 🁲, 🌔, 🙄, 🢅, 🨀
    function test_utf_length_with_four_bytes_chars() public {
        uint n = StringUtils.utfLength(first_byte(unicode"𒀁"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"𓃘"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"𓇼"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"𝅘𝅥𝅰"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"🁲"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"🌔"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"🙄"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"🢅"));
        assertEq(n, 4);

        n = StringUtils.utfLength(first_byte(unicode"🨀"));
        assertEq(n, 4);
    }

    function assertBytesEq(bytes memory a, bytes memory b) public {
        assertEq(a.length, b.length);
        for(uint i = 0; i < a.length; i++) {
            assertEq(a[i], b[i]);
        }
    }

    function test_first_n() public {
        bytes memory s = "abcdefghijklmnopqrstuvwxyz";
        bytes memory t = StringUtils.firstN(s, 5);
        assertBytesEq(t, bytes("abcde"));
        
        t = StringUtils.firstN(s, 0);
        assertBytesEq(t, bytes(""));

        t = StringUtils.firstN(s, 1);
        assertBytesEq(t, bytes("a"));
        
        t = StringUtils.firstN(s, 26);
        assertBytesEq(t, bytes("abcdefghijklmnopqrstuvwxyz"));

        t = StringUtils.firstN(s, 27);
        assertBytesEq(t, bytes("abcdefghijklmnopqrstuvwxyz"));

        t = StringUtils.firstN(s, 100);
        assertBytesEq(t, bytes("abcdefghijklmnopqrstuvwxyz"));

        s = "";
        t = StringUtils.firstN(s, 0);
        assertBytesEq(t, bytes(""));

        t = StringUtils.firstN(s, 1);
        assertBytesEq(t, bytes(""));

        t = StringUtils.firstN(s, 100);
        assertBytesEq(t, bytes(""));
    }

    function test_insert_before_ascii() public {
        bytes memory s = bytes("the quick brown fox");
        bytes memory t = StringUtils.insertBeforeAscii(s, 'k', '_');
        assertBytesEq(t, bytes("the quic_k brown fox"));

        s = bytes("and yet, poor fool, for all my lore");
        t = StringUtils.insertBeforeAscii(s, 'o', '_');
        assertBytesEq(t, bytes("and yet, p_o_or f_o_ol, f_or all my l_ore"));

        s = bytes("");
        t = StringUtils.insertBeforeAscii(s, 'o', '_');
        assertBytesEq(t, bytes(""));

        s = bytes("a");
        t = StringUtils.insertBeforeAscii(s, 'a', 'a');
        assertBytesEq(t, bytes("aa"));

        s = bytes("aa");
        t = StringUtils.insertBeforeAscii(s, 'a', 'a');
        assertBytesEq(t, bytes("aaaa"));

        s = bytes("aab");
        t = StringUtils.insertBeforeAscii(s, 'a', 'a');
        assertBytesEq(t, bytes("aaaab"));

        s = bytes(unicode"ì"); // C3 AC
        // TODO: Uncomment when forge is fixed
        //hevm.expectRevert("StringUtils: target must be ASCII");
        //t = StringUtils.insertBeforeAscii(s, 0xC3, '_');

        s = bytes(unicode"ìab");
        t = StringUtils.insertBeforeAscii(s, 'a', '_');
        assertBytesEq(t, bytes(unicode"ì_ab"));

        s = bytes(unicode"ìaìb");
        t = StringUtils.insertBeforeAscii(s, 'a', '_');
        assertBytesEq(t, bytes(unicode"ì_aìb"));
    }

    function test_insert_before_ascii_fuzz(bytes memory s, bytes1 charToFind, bytes1 charToInsert) public {
        if (charToFind >= 0x80) {
            // Prefix character, aka first byte of a multi byte character
            // TODO: Uncomment when forge is fixed
            //hevm.expectRevert("StringUtils: target must be ASCII");
            //StringUtils.insertBeforeAscii(s, charToFind, charToInsert);
        }
        else {
            bool validUtf = true;
            for (uint256 i = 0; i < s.length; i++) {
                if (StringUtils.utfLength(s[i]) + i > s.length) {
                    validUtf = false;
                }
            }
            if (validUtf) {
                bytes memory t = wrapper.wrappedInsertBeforeAscii(s, charToFind, charToInsert);

                for (uint256 i = 0; i < t.length; i += StringUtils.utfLength(t[i])) {
                    if (t[i] == charToFind) {
                        assertEq(t[i-1], charToInsert);
                    }
                }
            } else {
                hevm.expectRevert("StringUtils: not a valid UTF-8 string");
                wrapper.wrappedInsertBeforeAscii(s, charToFind, charToInsert);
            }
        }
    }
}

