require "../../spec_helper"
require "../../../src/utils/worker_threads"

describe Noir::WorkerThreads do
  it "returns results in input order however the threads finish" do
    items = (1..300).to_a
    # Uneven work so later items often finish first.
    results = Noir::WorkerThreads.map(items) do |n|
      acc = 0
      ((n * 7919) % 2000).times { |i| acc &+= i }
      n * 2
    end
    results.should eq(items.map { |n| n * 2 })
  end

  it "maps an element whose block raises to nil and keeps the rest" do
    results = Noir::WorkerThreads.map([1, 2, 3]) do |n|
      raise "boom" if n == 2
      n.to_s
    end
    results.should eq(["1", nil, "3"])
  end

  it "handles an empty input" do
    Noir::WorkerThreads.map([] of Int32) { |n| n }.should be_empty
  end
end
