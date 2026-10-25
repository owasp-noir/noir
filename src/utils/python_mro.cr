module Noir::PythonMRO
  MAX_DEPTH = 10

  # Python's C3 method resolution order of `root`: the class first, then
  # its bases such that every class precedes its own bases and the base
  # lists keep their left-to-right order (`class D(L, R)` with `L(B)`,
  # `R(B)` is D, L, R, B). `bases` yields a class's direct bases that can
  # be resolved; unresolvable ones are left out. A hierarchy C3 rejects
  # falls back to the remaining classes in base order.
  def self.linearize(root : T, &bases : T -> Array(T)) : Array(T) forall T
    linearize(root, bases, [] of T, 0)
  end

  private def self.linearize(node : T, bases : T -> Array(T), visiting : Array(T), depth : Int32) : Array(T) forall T
    return [node] if depth > MAX_DEPTH || visiting.includes?(node)
    visiting << node
    parents = bases.call(node).uniq
    seqs = parents.map { |parent| linearize(parent, bases, visiting, depth + 1) }
    seqs << parents.dup
    visiting.pop
    result = [node]
    seqs.reject!(&.empty?)
    until seqs.empty?
      head = seqs.map(&.first).find { |cand| seqs.none? { |seq| seq.index(cand).try(&.> 0) } }
      unless head
        seqs.each { |seq| seq.each { |cls| result << cls unless result.includes?(cls) } }
        break
      end
      result << head unless result.includes?(head)
      seqs.each { |seq| seq.shift if seq.first == head }
      seqs.reject!(&.empty?)
    end
    result
  end
end
