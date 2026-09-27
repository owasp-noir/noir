require "wait_group"

# A small pool of threads for work that is a pure function of its input.
#
# Crystal 1.21 runs every program on the execution-context runtime, so noir
# can put fibers on other threads without new compile flags. Only *pure*
# work goes here — reading a file, parsing a source into a fresh result —
# never anything that touches `CodeLocator`, an analyzer's instance state
# or the logger. Callers keep everything stateful on their own fiber and
# consume the pool's results in their original order, which is what keeps
# a scan's output independent of thread timing.
module Noir::WorkerThreads
  # Past four threads the measured gains flatten out (file reads on a 26k-file
  # tree: 1.29s sequential, 0.46s with 4, 0.40–0.44s with 8).
  MAX_THREADS = 4

  def self.count : Int32
    System.cpu_count.to_i.clamp(1, MAX_THREADS)
  end

  # Execution contexts are the default runtime from Crystal 1.21 on; 1.19
  # and 1.20 (which `shard.yml` still admits) only have them behind
  # `-Dexecution_context`, and `-Dwithout_mt` turns them off. Without them
  # the work runs as ordinary fibers on the calling thread: sequential
  # again, with identical results.
  {% if Fiber.has_constant?(:ExecutionContext) %}
    @@context : Fiber::ExecutionContext::Parallel?

    # One context for the process, created on first use. Contexts are not
    # torn down, so a per-call context would leak threads across the many
    # scans a spec run performs.
    def self.context : Fiber::ExecutionContext::Parallel
      @@context ||= Fiber::ExecutionContext::Parallel.new("noir-workers", count)
    end

    def self.spawn(name : String, &block : ->) : Nil
      context.spawn(name: name, &block)
    end
  {% else %}
    def self.spawn(name : String, &block : ->) : Nil
      ::spawn(name: name, &block)
    end
  {% end %}

  # `block` applied to every element of `items` on the pool, returned in
  # input order.
  #
  # An element whose block raises comes back as nil. That makes this an
  # optimisation callers can fall back from: they recompute a nil element on
  # their own fiber, where it raises (or not) exactly as it always did.
  def self.map(items : Array(T), &block : T -> U) : Array(U?) forall T, U
    results = Array(U?).new(items.size, nil)
    return results if items.empty?

    workers = {count, items.size}.min
    jobs = Channel(Int32).new(items.size)
    replies = Channel(Tuple(Int32, U?)).new(workers * 4)
    items.size.times { |index| jobs.send(index) }
    jobs.close

    workers.times do
      spawn("noir-map") do
        while index = jobs.receive?
          value = begin
            block.call(items[index])
          rescue
            nil
          end
          replies.send({index, value})
        end
      end
    end

    items.size.times do
      index, value = replies.receive
      results[index] = value
    end
    results
  end
end
