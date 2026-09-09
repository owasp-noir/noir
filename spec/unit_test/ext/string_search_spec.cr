require "spec"
require "../../../src/ext/string_search"

# The fast path must be indistinguishable from the stdlib search. The
# reference is the stdlib algorithm itself, re-implemented here verbatim
# (Rabin-Karp stepping by decoded character), so every case below checks
# the override against what `String#index` returned before it existed.
private PRIME_RK = 16777619_u32

private def reference_index(hay : String, search : String, offset = 0) : Int32?
  offset += hay.size if offset < 0
  return if offset < 0
  return hay.size < offset ? nil : offset if search.empty?

  search_hash = 0u32
  search.each_byte { |b| search_hash = search_hash &* PRIME_RK &+ b }
  pow = PRIME_RK &** search.bytesize

  char_index = 0
  pointer = hay.to_unsafe
  end_pointer = pointer + hay.bytesize
  while char_index < offset && pointer < end_pointer
    pointer += char_bytesize_at(pointer)
    char_index += 1
  end
  head_pointer = pointer

  hash = 0u32
  hash_end_pointer = pointer + search.bytesize
  return if hash_end_pointer > end_pointer
  while pointer < hash_end_pointer
    hash = hash &* PRIME_RK &+ pointer.value
    pointer += 1
  end

  while true
    if hash == search_hash && head_pointer.memcmp(search.to_unsafe, search.bytesize) == 0
      return char_index
    end
    char_bytesize = char_bytesize_at(head_pointer)
    return if pointer + char_bytesize > end_pointer
    char_bytesize.times do
      hash = hash &* PRIME_RK &+ pointer.value &- pow &* head_pointer.value
      pointer += 1
      head_pointer += 1
    end
    char_index += 1
  end
end

private def reference_byte_index(hay : String, search : String, offset = 0) : Int32?
  offset += hay.bytesize if offset < 0
  return if offset < 0
  return hay.bytesize < offset ? nil : offset if search.empty?
  last = hay.bytesize - search.bytesize
  i = offset
  while i <= last
    return i if (hay.to_unsafe + i).memcmp(search.to_unsafe, search.bytesize) == 0
    i += 1
  end
  nil
end

# Mirrors `String.char_bytesize_at` (protected in the stdlib).
private def char_bytesize_at(bytes : Pointer(UInt8)) : Int32
  first = bytes.value
  return 1 if first < 0x80
  return 1 if first < 0xc2
  second = bytes[1]
  return 1 if (second & 0xc0) != 0x80
  return 2 if first < 0xe0
  third = bytes[2]
  return 1 if (third & 0xc0) != 0x80
  if first < 0xf0
    return 1 if first == 0xe0 && second < 0xa0
    return 1 if first == 0xed && second >= 0xa0
    return 3
  end
  return 1 if first == 0xf0 && second < 0x90
  return 1 if first == 0xf4 && second >= 0x90
  return 1 if first >= 0xf5
  return 1 if (bytes[3] & 0xc0) != 0x80
  4
end

private def check(hay : String, needle : String, offset = 0)
  hay.index(needle, offset).should eq(reference_index(hay, needle, offset)), "index #{hay.inspect} #{needle.inspect} #{offset}"
  hay.byte_index(needle, offset).should eq(reference_byte_index(hay, needle, offset)), "byte_index #{hay.inspect} #{needle.inspect} #{offset}"
end

describe "Noir::FastSearch" do
  it "matches the stdlib on ASCII haystacks" do
    hay = "from flask import Flask\napp = Flask(__name__)\n@app.route('/x')\n"
    ["flask", "Flask(", "@app.route(", "\n@", "route('/x')\n", "missing", "f", "\n", hay, hay + "x", ""].each do |needle|
      [0, 1, 5, hay.size - 1, hay.size, hay.size + 1, -1, -5, -hay.size, -hay.size - 1].each do |offset|
        check(hay, needle, offset)
      end
    end
  end

  it "matches the stdlib on multi-byte haystacks, before and after the non-ASCII run" do
    hay = "# 라우터 설정\nfrom flask import Flask # é\napp.route('/한글')\n"
    ["flask", "라우터", "설정\n", "é", "/한글", "글')", "route", "\n", "missing", "x", ""].each do |needle|
      (0..hay.size + 1).each { |offset| check(hay, needle, offset) }
      check(hay, needle, -1)
      check(hay, needle, -3)
    end
  end

  it "matches the stdlib on malformed UTF-8, where the stdlib skips byte offsets" do
    bad = String.new(Bytes[0xE2, 0x61, 0x62, 0x0A, 0xC3, 0x28, 0x61, 0x62, 0xFF, 0x61])
    ["ab", "a", "b", "\n", "(", "(a", "\xFFa", "\xE2a"].each do |needle|
      (0..bad.size + 1).each { |offset| check(bad, needle, offset) }
    end
    # The stdlib steps over the 0xE2 lead byte as one char and does not
    # see "ab" at byte 1; the override must not either.
    bad.index("ab").should eq(reference_index(bad, "ab"))
  end

  it "matches the stdlib on random inputs" do
    alphabet = ["a", "b", "\n", " ", "(", "é", "한", "\u{1F600}"]
    rng = Random.new(20260909)
    500.times do
      hay = String.build { |io| rng.rand(0..40).times { io << alphabet.sample(rng) } }
      needle = String.build { |io| rng.rand(0..4).times { io << alphabet.sample(rng) } }
      check(hay, needle, 0)
      check(hay, needle, rng.rand(-3..hay.size + 1))
      needle.index(hay).should eq(reference_index(needle, hay))
    end
  end

  it "matches the stdlib on random malformed byte strings" do
    rng = Random.new(7)
    300.times do
      hay = String.new(Bytes.new(rng.rand(0..24)) { rng.rand(0..255).to_u8 })
      needle = String.new(Bytes.new(rng.rand(1..3)) { rng.rand(0..255).to_u8 })
      check(hay, needle, 0)
      check(hay, needle, rng.rand(0..hay.size))
      needle = hay.byte_slice(rng.rand(0..hay.bytesize), rng.rand(0..3)) rescue ""
      check(hay, needle, 0) unless needle.empty?
    end
  end

  it "keeps includes? in sync" do
    "app.use('/api', router)".includes?(".use(").should be_true
    "app.use ('/api', router)".includes?(".use(").should be_false
    "".includes?("").should be_true
    "abc".includes?("").should be_true
  end
end
