# A memchr-driven fast path for `String#index(String)`, `String#byte_index(String)`
# and therefore `String#includes?(String)`.
#
# The stdlib implements substring search as a Rabin-Karp rolling hash: one
# multiply-add per byte, no vectorisation, roughly 0.8 GB/s. Every detector
# and analyzer gates its regexes with `content.includes?("...")`, so on a
# scan that reads tens of megabytes of source the search itself was a
# measurable share of the wall clock (profiled on superset: ~9% of the
# Flask analyzer, ~50% of the Express analyzer).
#
# The replacement scans for the rarest byte of the needle with `memchr`
# (vectorised in every libc) and confirms each candidate with `memcmp`.
# It tests every byte offset, so a miss here is a miss in the stdlib too.
# A hit is returned directly only when the stdlib would have found the
# same one: for `byte_index` always (both are byte-level), for `index`
# only when every byte before the hit is ASCII, because the stdlib steps
# by decoded character and can skip over a match that begins inside a
# multi-byte or malformed sequence. Every other case falls through to
# `previous_def`, so the result is identical by construction rather than
# by argument. The fall-through is bounded by the old cost: it only runs
# after a hit, and the stdlib scan stops at that same hit.
module Noir::FastSearch
  # Rank of each byte value by how often it appears in source code, 0 =
  # most common. Measured over ~400 MB of Python, TypeScript, Go, Ruby,
  # Java, PHP, C#, Rust, JSON, YAML and Markdown from real repositories.
  # Only the ordering matters: the needle byte with the highest rank is
  # the one `memchr` looks for, so a needle like `.route(` is located by
  # its `(` or `r`, not by the `e` or `t` that appear on every line.
  BYTE_RARITY = UInt8.static_array(
    199, 210, 213, 221, 222, 223, 224, 212, 225, 22, 9, 226, 227, 196, 228, 217,
    229, 230, 218, 231, 232, 215, 233, 234, 216, 235, 236, 211, 237, 238, 239, 240,
    0, 92, 13, 78, 106, 97, 90, 38, 27, 28, 74, 107, 23, 25, 16, 18,
    34, 39, 44, 47, 54, 65, 67, 75, 59, 77, 24, 58, 32, 31, 29, 104,
    50, 46, 76, 48, 61, 51, 68, 80, 82, 49, 103, 85, 63, 66, 57, 64,
    56, 105, 52, 40, 45, 73, 83, 84, 111, 98, 113, 69, 99, 70, 180, 19,
    81, 4, 30, 12, 14, 1, 26, 20, 21, 6, 62, 35, 10, 17, 8, 7,
    11, 71, 5, 3, 2, 15, 37, 36, 43, 33, 79, 41, 89, 42, 192, 214,
    53, 102, 101, 96, 132, 147, 149, 150, 137, 174, 167, 166, 127, 158, 186, 163,
    152, 175, 176, 182, 129, 133, 162, 164, 172, 131, 169, 173, 151, 165, 179, 156,
    155, 116, 183, 170, 109, 144, 161, 118, 139, 123, 145, 159, 171, 140, 160, 138,
    108, 115, 135, 136, 134, 114, 126, 128, 93, 130, 55, 121, 125, 119, 110, 143,
    241, 242, 193, 88, 122, 148, 190, 202, 197, 188, 201, 206, 200, 205, 120, 154,
    72, 86, 194, 198, 195, 117, 185, 100, 94, 112, 178, 146, 203, 208, 207, 209,
    87, 91, 60, 95, 177, 124, 142, 153, 168, 181, 187, 157, 141, 184, 243, 189,
    191, 244, 245, 204, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 220, 219,
  )

  # Byte offset of the first occurrence of `needle` in `hay` at or after
  # byte `offset`, or `nil`. Pure byte semantics: every offset is tried.
  def self.byte_index(hay : String, needle : String, offset : Int32) : Int32?
    hay_size = hay.bytesize
    needle_size = needle.bytesize
    return if needle_size == 0 || offset < 0 || offset + needle_size > hay_size

    hay_ptr = hay.to_unsafe
    needle_ptr = needle.to_unsafe
    pivot = rarest_byte_offset(needle_ptr, needle_size)
    target = needle_ptr[pivot].to_i32

    # A candidate starts at s in [offset, hay_size - needle_size]; its
    # pivot byte sits at s + pivot, so that is the window memchr walks.
    scan = hay_ptr + offset + pivot
    last = hay_ptr + (hay_size - needle_size) + pivot
    while scan <= last
      found = LibC.memchr(scan.as(Void*), target, (last - scan + 1).to_u64)
      return if found.null?
      candidate = found.as(UInt8*) - pivot
      if candidate.memcmp(needle_ptr, needle_size) == 0
        return (candidate - hay_ptr).to_i32
      end
      scan = found.as(UInt8*) + 1
    end
    nil
  end

  # True when every byte in `[0, count)` is ASCII, i.e. the stdlib's
  # character stepping visits every byte offset in that prefix.
  def self.ascii_prefix?(ptr : UInt8*, count : Int32) : Bool
    i = 0
    while i < count
      return false if ptr[i] >= 0x80
      i += 1
    end
    true
  end

  private def self.rarest_byte_offset(needle_ptr : UInt8*, needle_size : Int32) : Int32
    best = 0
    best_rank = BYTE_RARITY[needle_ptr[0]]
    i = 1
    while i < needle_size
      rank = BYTE_RARITY[needle_ptr[i]]
      if rank > best_rank
        best_rank = rank
        best = i
      end
      i += 1
    end
    best
  end
end

class String
  def index(search : String, offset = 0) : Int32?
    if offset == 0 && !search.empty?
      pos = Noir::FastSearch.byte_index(self, search, 0)
      return unless pos
      return pos if Noir::FastSearch.ascii_prefix?(to_unsafe, pos)
    end
    previous_def
  end

  def byte_index(search : String, offset = 0) : Int32?
    if offset >= 0 && !search.empty?
      return Noir::FastSearch.byte_index(self, search, offset)
    end
    previous_def
  end
end
