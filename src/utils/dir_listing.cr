require "wait_group"
require "./worker_threads"

# One directory's entries and their `lstat` results, taken off the thread
# that walks the tree.
#
# The detect walk spent most of its time in `opendir`, `readdir`, `lstat`
# and one `access` per directory (the `shard.yml` check), all on the thread
# that also dispatches detection. The walk submits each directory here when
# it pushes it and takes the listing when it pops it, so the syscalls run
# ahead on `Noir::WorkerThreads.walk_context` while everything the walk
# decides — pruning, filters, order — is unchanged.
module Noir::DirListing
  # `stat_error` is the reason `File.info?` came back nil, taken from a
  # second, raising `File.info` exactly as the walk used to.
  record Entry, name : String, info : File::Info?, stat_error : String?

  # `error` is what `Dir.each_child` raised, if it did. `entries` then holds
  # the entries it yielded first — the walk processes those before
  # recording the directory as unlistable, as it did when it listed inline.
  # Anything other than a `File::Error` is carried here too, so the walk
  # can re-raise it rather than wait on a reply that never comes.
  record Listing, has_shard : Bool, entries : Array(Entry), error : Exception?

  def self.list(dir : String) : Listing
    has_shard = File.exists?(File.join(dir, "shard.yml"))
    entries = [] of Entry
    error = nil
    begin
      Dir.each_child(dir) do |name|
        full_path = File.join(dir, name)
        info = File.info?(full_path, follow_symlinks: false)
        entries << Entry.new(name, info, info ? nil : stat_failure(full_path))
      end
    rescue e : File::Error
      error = e
    end
    Listing.new(has_shard, entries, error)
  end

  private def self.stat_failure(full_path : String) : String
    File.info(full_path, follow_symlinks: false)
    "stat returned no information"
  rescue e : File::Error
    e.message.presence || e.class.name
  end

  # Lists submitted directories on the walk context. Every submission gets
  # exactly one listing, and a worker never blocks on a reply, so a caller
  # that stops receiving (a walk that raised) cannot wedge the pool.
  class Pool
    @jobs : Channel(Tuple(String, Channel(Listing)))
    @done : WaitGroup

    def initialize(workers : Int32 = Noir::WorkerThreads.count)
      @jobs = Channel(Tuple(String, Channel(Listing))).new(1024)
      @done = WaitGroup.new(workers)
      workers.times do
        Noir::WorkerThreads.spawn_walker("noir-walk") { work }
      end
    end

    def submit(dir : String) : Channel(Listing)
      reply = Channel(Listing).new(1)
      @jobs.send({dir, reply})
      reply
    end

    # Idempotent: safe to call from both the normal and the error path.
    def close : Nil
      @jobs.close
      @done.wait
    end

    private def work : Nil
      while job = @jobs.receive?
        dir, reply = job
        listing = begin
          Noir::DirListing.list(dir)
        rescue e
          Listing.new(false, [] of Entry, e)
        end
        reply.send(listing)
      end
    ensure
      @done.done
    end
  end
end
