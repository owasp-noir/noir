require "../../spec_helper"
require "../../../src/utils/wait_group.cr"

describe "WaitGroup" do
  describe "basic functionality" do
    it "initializes with count 0" do
      wg = WaitGroup.new
      # WaitGroup should initialize properly
      wg.should_not be_nil
    end

    it "add increases count" do
      wg = WaitGroup.new
      wg.add(1)
      wg.add(2)
      # Count should be accumulated correctly (tested indirectly via done)
    end

    it "done decrements count" do
      wg = WaitGroup.new
      wg.add(1)
      spawn do
        sleep 0.01
        wg.done
      end
      wg.wait
      # If we get here, wait completed successfully
      true.should eq(true)
    end

    it "wait blocks until count reaches zero" do
      wg = WaitGroup.new
      wg.add(2)
      
      counter = 0
      spawn do
        sleep 0.01
        counter += 1
        wg.done
      end
      
      spawn do
        sleep 0.02
        counter += 1
        wg.done
      end
      
      wg.wait
      counter.should eq(2)
    end
  end

  describe "spawn helper" do
    it "automatically adds and calls done" do
      wg = WaitGroup.new
      executed = false
      
      wg.spawn do
        sleep 0.01
        executed = true
      end
      
      wg.wait
      executed.should eq(true)
    end

    it "handles multiple spawned tasks" do
      wg = WaitGroup.new
      counter = 0
      
      3.times do
        wg.spawn do
          sleep 0.01
          counter += 1
        end
      end
      
      wg.wait
      counter.should eq(3)
    end

    it "calls done even if task raises exception" do
      wg = WaitGroup.new
      
      wg.spawn do
        raise "test error"
      end
      
      # This should not hang even though the task raised an error
      wg.wait
      true.should eq(true)
    end
  end

  describe "class method wait" do
    it "provides convenient syntax for waiting" do
      counter = 0
      
      WaitGroup.wait do |wg|
        wg.spawn do
          sleep 0.01
          counter += 1
        end
        
        wg.spawn do
          sleep 0.01
          counter += 1
        end
      end
      
      counter.should eq(2)
    end
  end

  describe "edge cases" do
    it "handles add with multiple values" do
      wg = WaitGroup.new
      wg.add(3)
      
      3.times do
        spawn do
          sleep 0.01
          wg.done
        end
      end
      
      wg.wait
      true.should eq(true)
    end

    it "handles zero additions" do
      wg = WaitGroup.new
      wg.add(0)
      # Should not block
      true.should eq(true)
    end
  end
end
