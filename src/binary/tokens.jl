# SPDX-License-Identifier: MIT
#
# The token table of the binary encoding (omstd20 §3.2.1, §3.2.2).
#
# "The identifier is stored in the first five bits (1 to 5). Bit 6 is used as a
# status bit which is currently only used for managing streaming of some basic
# objects. Bits 7 and 8 are the sharing flag and the long flag."
#
# So a tag byte is  long | share | stream | identifier, and the identifier is the
# low five bits. Everything in this file is that sentence, written out.

const TOK_INT = 0x01          # small integer
const TOK_BIGINT = 0x02       # big integer: length, sign/base, digits
const TOK_FLOAT = 0x03        # IEEE 754 double, most significant byte first
const TOK_BYTES = 0x04
const TOK_VAR = 0x05
const TOK_STR8 = 0x06         # ISO-8859-1
const TOK_STR16 = 0x07        # UTF-16
const TOK_SYMBOL = 0x08
const TOK_CDBASE = 0x09       # scopes over exactly one following object
const TOK_FOREIGN = 0x0c
const TOK_APP = 0x10
const TOK_APP_END = 0x11
const TOK_ATTR = 0x12
const TOK_ATTR_END = 0x13
const TOK_ATP = 0x14
const TOK_ATP_END = 0x15
const TOK_ERROR = 0x16
const TOK_ERROR_END = 0x17
const TOK_OBJ = 0x18
const TOK_OBJ_END = 0x19
const TOK_BIND = 0x1a
const TOK_BIND_END = 0x1b
const TOK_BVAR = 0x1c
const TOK_BVAR_END = 0x1d
const TOK_REF = 0x1e          # internal reference, by ordinal
const TOK_REF_EXT = 0x1f      # external reference, by URI

const FLAG_STREAM = 0x20      # a further packet of this basic object follows
const FLAG_SHARE = 0x40       # §3.2.4.1 back-reference, or §3.2.4.2 "referenced later"
const FLAG_LONG = 0x80        # lengths are four bytes, not one

@inline identifier(tag::UInt8) = tag & 0x1f
@inline islong(tag::UInt8) = tag & FLAG_LONG != 0
@inline isshared(tag::UInt8) = tag & FLAG_SHARE != 0
@inline isstreamed(tag::UInt8) = tag & FLAG_STREAM != 0

# The one-byte forms run out at 255; §3.2.2 sets the threshold as "greater than
# or equal to 256" for every length field in the encoding.
@inline needs_long(n::Integer) = n >= 256

# The sign and base of a big integer share one byte: "'+' (0x2B) or '-' (0x2D)
# for the sign or-ed with the base mask bits".
const SIGN_PLUS = 0x2b
const SIGN_MINUS = 0x2d
const BASE_MASK = 0xc0
const BASE_10 = 0x00
const BASE_16 = 0x40
const BASE_256 = 0x80
