class WaitGroup
  @count : Int32
  @mutex : Mutex
  @channel : Channel(Nil)

  def initialize
    @count = 0
    @mutex = Mutex.new
    @channel = Channel(Nil).new
  end

  def add(delta : Int32)
    @mutex.synchronize do
      @count += delta
    end
  end

  def done
    @mutex.synchronize do
      @count -= 1
      if @count == 0
        @channel.send(nil)
      end
    end
  end

  def wait
    @channel.receive
  end

  def spawn(&block : -> Void)
    add(1)
    ::spawn do
      begin
        block.call
      ensure
        done
      end
    end
  end

  def self.wait(&)
    wg = new
    yield wg
    wg.wait
  end
end
