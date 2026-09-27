require "wait_group"
require "./text_file"

# Reads files on a small pool of threads.
#
# The detect walk used to read every file on the one thread that also runs
# detection, so each `open`/`read`/`close` stalled everything else — on a
# warm page cache macOS spends ~50µs of syscall time per file, and a cold
# one waits on the disk. Reads are independent and touch no shared state,
# so they can run in parallel; everything done *with* a file's content stays
# where it was.
#
# Callers get a reply channel per submitted path and receive from those in
# whatever order they need — the detector receives them in walk order, so
# registration order, detector dispatch and the content cache see exactly
# the sequence a sequential walk produced.
#
# A worker never blocks on a reply (each reply channel holds one outcome),
# and every submitted path gets exactly one outcome, errors included: a
# missing reply would leave the receiver waiting forever.
class Noir::ReadPool
  record Outcome, content : String? = nil, binary : Bool = false, error : Exception? = nil

  # Past four readers the gain flattens out (measured on a 26k-file tree:
  # 1.29s sequential, 0.46s with 4, 0.40–0.44s with 8), and the pool only
  # has to stay ahead of the single fiber consuming its results.
  MAX_WORKERS = 4

  # Execution contexts are the default runtime from Crystal 1.21 on; 1.19
  # and 1.20 (which `shard.yml` still admits) only have them behind
  # `-Dexecution_context`, and `-Dwithout_mt` turns them off. Without
  # them the workers run as ordinary fibers on the calling thread: the
  # reads are sequential again, but every other behaviour is the same.
  {% if Fiber.has_constant?(:ExecutionContext) %}
    @@context : Fiber::ExecutionContext::Parallel?

    # One context for the process, created on first use. Contexts are not
    # torn down, so a per-scan context would leak threads across the many
    # scans a spec run performs.
    def self.context : Fiber::ExecutionContext::Parallel
      @@context ||= Fiber::ExecutionContext::Parallel.new("noir-read", worker_count)
    end
  {% end %}

  def self.worker_count : Int32
    System.cpu_count.to_i.clamp(1, MAX_WORKERS)
  end

  @jobs : Channel(Tuple(String, Channel(Outcome)))
  @done : WaitGroup

  def initialize(workers : Int32 = ReadPool.worker_count)
    @jobs = Channel(Tuple(String, Channel(Outcome))).new(workers * 16)
    @done = WaitGroup.new(workers)
    workers.times { spawn_worker }
  end

  private def spawn_worker : Nil
    {% if Fiber.has_constant?(:ExecutionContext) %}
      ReadPool.context.spawn(name: "noir-read") { work }
    {% else %}
      spawn(name: "noir-read") { work }
    {% end %}
  end

  private def work : Nil
    while job = @jobs.receive?
      path, reply = job
      reply.send(read(path))
    end
  ensure
    @done.done
  end

  # Queue `path` for reading. The returned channel yields its `Outcome`.
  def submit(path : String) : Channel(Outcome)
    reply = Channel(Outcome).new(1)
    @jobs.send({path, reply})
    reply
  end

  # No more submissions; returns once every worker has finished.
  def close : Nil
    @jobs.close
    @done.wait
  end

  # `Noir::TextFile.read` plus the binary sniff the walk applies right
  # after it, both pure functions of the bytes.
  private def read(path : String) : Outcome
    content = Noir::TextFile.read(path)
    Outcome.new(content: content, binary: content.to_slice.includes?(0_u8))
  rescue e
    Outcome.new(error: e)
  end
end
