require 'abstract_unit'

# Allow LittleFanout to be cleaned.
class ActiveSupport::Orchestra::LittleFanout
  def clear
    @listeners.clear
  end
end

class OrchestraEventTest < Test::Unit::TestCase
  def test_events_are_initialized_with_name_and_payload
    event = event(:foo, :payload => :bar)
    assert_equal :foo, event.name
    assert_equal Hash[:payload => :bar], event.payload
  end

  def test_events_consumes_information_given_as_payload
    event = event(:foo, :time => (time = Time.now), :result => 1, :duration => 10)

    assert_equal Hash.new, event.payload
    assert_equal time, event.time
    assert_equal 1, event.result
    assert_equal 10, event.duration
  end

  def test_event_is_parent_based_on_time_frame
    parent    = event(:foo, :time => Time.utc(2009), :duration => 10000)
    child     = event(:foo, :time => Time.utc(2009, 01, 01, 0, 0, 1), :duration => 1000)
    not_child = event(:foo, :time => Time.utc(2009, 01, 01, 0, 0, 1), :duration => 10000)

    assert parent.parent_of?(child)
    assert !child.parent_of?(parent)
    assert !parent.parent_of?(not_child)
    assert !not_child.parent_of?(parent)
  end

  protected

    def event(*args)
      ActiveSupport::Orchestra::Event.new(*args)
    end
end

class OrchestraMainTest < Test::Unit::TestCase
  def setup
    @events = []
    Thread.abort_on_exception = true
    ActiveSupport::Orchestra.subscribe { |event| @events << event }
  end

  def teardown
    Thread.abort_on_exception = false
    ActiveSupport::Orchestra.queue.clear
  end

  def test_orchestra_returns_action_result
    result = ActiveSupport::Orchestra.instrument(:awesome, :payload => "orchestra") do
      1 + 1
    end

    assert_equal 2, result
  end

  def test_events_are_published_to_a_listener
    ActiveSupport::Orchestra.instrument(:awesome, :payload => "orchestra") do
      1 + 1
    end

    sleep(0.1)

    assert_equal 1, @events.size
    assert_equal :awesome, @events.last.name
    assert_equal Hash[:payload => "orchestra"], @events.last.payload
  end

  def test_nested_events_can_be_instrumented
    ActiveSupport::Orchestra.instrument(:awesome, :payload => "orchestra") do
      ActiveSupport::Orchestra.instrument(:wot, :payload => "child") do
        1 + 1
      end

      sleep(0.1)

      assert_equal 1, @events.size
      assert_equal :wot, @events.first.name
      assert_equal Hash[:payload => "child"], @events.first.payload
    end

    sleep(0.1)

    assert_equal 2, @events.size
    assert_equal :awesome, @events.last.name
    assert_equal Hash[:payload => "orchestra"], @events.last.payload
    assert_in_delta 100, @events.last.duration, 70
  end

  def test_event_is_pushed_even_if_block_fails
    ActiveSupport::Orchestra.instrument(:awesome, :payload => "orchestra") do
      raise "OMG"
    end rescue RuntimeError

    sleep(0.1)

    assert_equal 1, @events.size
    assert_equal :awesome, @events.last.name
    assert_equal Hash[:payload => "orchestra"], @events.last.payload
  end

  def test_event_is_pushed_even_without_block
    ActiveSupport::Orchestra.instrument(:awesome, :payload => "orchestra")
    sleep(0.1)

    assert_equal 1, @events.size
    assert_equal :awesome, @events.last.name
    assert_equal Hash[:payload => "orchestra"], @events.last.payload
  end

  def test_subscriber_with_pattern
    @another = []
    ActiveSupport::Orchestra.subscribe("cache"){ |event| @another << event }
    ActiveSupport::Orchestra.instrument(:cache){ 1 }

    sleep(0.1)

    assert_equal 1, @another.size
    assert_equal :cache, @another.first.name
    assert_equal 1, @another.first.result
  end

  def test_subscriber_with_pattern_as_regexp
    @another = []
    ActiveSupport::Orchestra.subscribe(/cache/){ |event| @another << event }

    ActiveSupport::Orchestra.instrument(:something){ 0 }
    ActiveSupport::Orchestra.instrument(:cache){ 1 }

    sleep(0.1)

    assert_equal 1, @another.size
    assert_equal :cache, @another.first.name
    assert_equal 1, @another.first.result
  end

  def test_with_several_consumers_and_several_events
    @another = []
    ActiveSupport::Orchestra.subscribe { |event| @another << event }

    1.upto(100) do |i|
      ActiveSupport::Orchestra.instrument(:value){ i }
    end

    sleep 0.1

    assert_equal 100, @events.size
    assert_equal :value, @events.first.name
    assert_equal 1, @events.first.result
    assert_equal 100, @events.last.result

    assert_equal 100, @another.size
    assert_equal :value, @another.first.name
    assert_equal 1, @another.first.result
    assert_equal 100, @another.last.result
  end
end