require "spec"
require "../../../src/utils/python_mro"

private def mro(root : String, bases : Hash(String, Array(String))) : Array(String)
  Noir::PythonMRO.linearize(root) { |cls| bases[cls]? || [] of String }
end

describe Noir::PythonMRO do
  describe ".linearize" do
    it "follows a single inheritance chain" do
      bases = {"C" => ["B"], "B" => ["A"]}
      mro("C", bases).should eq(%w[C B A])
    end

    it "puts both parents before their shared base" do
      bases = {"D" => ["L", "R"], "L" => ["B"], "R" => ["B"]}
      mro("D", bases).should eq(%w[D L R B])
    end

    it "keeps the left-to-right order of the base list" do
      bases = {"D" => ["R", "L"], "L" => ["B"], "R" => ["B"]}
      mro("D", bases).should eq(%w[D R L B])
    end

    it "returns only the class when it has no resolvable bases" do
      mro("K", {} of String => Array(String)).should eq(%w[K])
    end

    it "lists a base that is named twice once" do
      bases = {"C" => ["A", "A"]}
      mro("C", bases).should eq(%w[C A])
    end

    it "returns instead of looping on a cycle" do
      bases = {"A" => ["B"], "B" => ["A"]}
      mro("A", bases).should eq(%w[A B])
    end

    it "returns a class that is its own base once" do
      bases = {"A" => ["A"]}
      mro("A", bases).should eq(%w[A])
    end

    # `X(A, B)` wants A before B and `Y(B, A)` wants B before A, so Python
    # raises a TypeError here. The remaining classes follow in base order.
    it "falls back to base order for a hierarchy C3 rejects" do
      bases = {"Z" => ["X", "Y"], "X" => ["A", "B"], "Y" => ["B", "A"]}
      mro("Z", bases).should eq(%w[Z X Y A B])
    end

    it "stops following bases past MAX_DEPTH" do
      depth = Noir::PythonMRO::MAX_DEPTH
      # C0(C1), C1(C2), ... well past the limit.
      bases = Hash(String, Array(String)).new
      (0...depth + 5).each { |i| bases["C#{i}"] = ["C#{i + 1}"] }

      result = mro("C0", bases)
      result.should eq((0..depth + 1).map { |i| "C#{i}" })
      result.should_not contain("C#{depth + 2}")
    end

    it "works on any type the block can resolve" do
      bases = {3 => [2, 1], 2 => [0], 1 => [0]}
      Noir::PythonMRO.linearize(3) { |cls| bases[cls]? || [] of Int32 }.should eq([3, 2, 1, 0])
    end
  end
end
