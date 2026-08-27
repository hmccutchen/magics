require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'
require_relative '../../app/seams.rb'
require_relative '../../app/owl_speech.rb'

# Minimal stand-ins for DragonRuby's args, which is an open structure. Only
# the parts OwlSpeech actually reads are modelled.
class FakeOwl
  attr_accessor :x, :depth, :w, :h, :lift

  def initialize
    @x    = 640
    @depth = 100.0
    @w    = Config::OWL_W
    @h    = Config::OWL_H
    @lift = Config::OWL_PERCH_LIFT
  end
end

class FakeState
  attr_accessor :resolved_regions, :revealed_seams, :seams, :tick_count,
                :owl, :owl_line, :owl_line_until, :owl_said, :owl_seen_seams

  def initialize
    @resolved_regions = []
    @revealed_seams   = []
    @tick_count       = 0
    @owl              = FakeOwl.new
    @owl_line_until   = 0
    @owl_said         = []
    @owl_seen_seams   = []
  end
end

# A click is a point that answers inside_rect?, which DragonRuby mixes into
# Hash via Geometry. Reimplemented here because that mixin is engine-side.
class FakeClick
  attr_reader :x, :y

  def initialize x, y
    @x = x
    @y = y
  end

  def inside_rect? rect
    @x >= rect[:x] && @x <= rect[:x] + rect[:w] &&
      @y >= rect[:y] && @y <= rect[:y] + rect[:h]
  end
end

class FakeMouse
  attr_accessor :click
end

class FakeInputs
  attr_reader :mouse

  def initialize
    @mouse = FakeMouse.new
  end
end

class FakeArgs
  attr_reader :state, :inputs

  def initialize
    @state  = FakeState.new
    @inputs = FakeInputs.new
  end

  # One tick, with an optional click this frame. Clicks are momentary in
  # DragonRuby, so it is cleared afterwards the way the engine would.
  def tick click = nil
    @inputs.mouse.click = click
    @state.tick_count  += 1
    OwlSpeech.update self
    @inputs.mouse.click = nil
  end

  def shut_up!
    @state.owl_line = nil
  end
end

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

# The centre of the owl's drawn rect, which is what a player aims at.
def owl_centre args
  owl  = args.state.owl
  rect = World.place owl.x, owl.depth, owl.w, owl.h, owl.lift

  FakeClick.new rect[:x] + (rect[:w] / 2), rect[:y] + (rect[:h] / 2)
end

puts 'loading the file runs assert_every_referenced_line_exists!'
check 'every referenced line is real',
      (OwlSpeech::STORY_TRIGGERS.values + [OwlSpeech::IDLE_LINE])
        .all? { |id| OwlSpeech::LINES.key? id },
      true

puts 'the owl says nothing unbidden'
args = FakeArgs.new
30.times { args.tick }
check 'silent while nothing happens', OwlSpeech.speaking?(args), false

puts 'walking about does not make it talk'
args = FakeArgs.new
args.state.owl.x = 100
args.tick
args.state.owl.x = 900
args.tick
check 'still silent', OwlSpeech.speaking?(args), false

puts 'clicking it makes it speak'
args = FakeArgs.new
args.tick owl_centre(args)
check 'speaking',              OwlSpeech.speaking?(args), true
check 'nothing to hint about', args.state.owl_line, OwlSpeech::IDLE_LINE

puts 'clicking elsewhere does not'
args = FakeArgs.new
args.tick FakeClick.new(10, 10)
check 'silent', OwlSpeech.speaking?(args), false

puts 'the padding makes it a fair target'
args   = FakeArgs.new
owl    = args.state.owl
owl.depth = Config::DEPTH_FAR          # smallest the bird ever draws
rect   = World.place owl.x, owl.depth, owl.w, owl.h, owl.lift
just_outside = FakeClick.new rect[:x] - (Config::OWL_CLICK_PADDING_PX - 1), rect[:y]
args.tick just_outside
check 'a near miss still counts', OwlSpeech.speaking?(args), true

puts 'a revealed seam makes it offer the hint unprompted'
args = FakeArgs.new
args.tick
Seams.reveal! args, :far_stand
args.tick
check 'speaking',      OwlSpeech.speaking?(args), true
check 'the doc\'s line', args.state.owl_line, :fool_reaches

puts 'the hint is offered once, not every tick'
args.shut_up!
60.times { args.tick }
check 'said exactly once', args.state.owl_said, [:fool_reaches]

puts 'asking again while the seam is still unactivated repeats the hint'
args.tick owl_centre(args)
check 'the same line, verbatim', args.state.owl_line, :fool_reaches
check 'both firings recorded',   args.state.owl_said, [:fool_reaches, :fool_reaches]

puts 'once the seam is activated there is nothing left to hint'
args.shut_up!
Regions.resolve! args, :far_stand
args.tick owl_centre(args)
check 'falls back to the idle line', args.state.owl_line, OwlSpeech::IDLE_LINE

puts 'a story hint is never dropped for being badly timed'
args = FakeArgs.new
args.tick owl_centre(args)                 # owl is mid-idle-line
check 'busy saying something else', args.state.owl_line, OwlSpeech::IDLE_LINE

Seams.reveal! args, :far_stand
args.tick
check 'hint did not barge in',  args.state.owl_line, OwlSpeech::IDLE_LINE
check 'and was not consumed',   args.state.owl_seen_seams, []

args.state.tick_count = args.state.owl_line_until
args.tick
check 'it lands as soon as the owl is free', args.state.owl_line, :fool_reaches
check 'edge consumed only now', args.state.owl_seen_seams, [:far_stand]

puts 'it finishes its thought rather than being interrupted'
args = FakeArgs.new
args.tick owl_centre(args)
args.tick owl_centre(args)
check 'one firing, not two', args.state.owl_said, [OwlSpeech::IDLE_LINE]

puts 'the line expires on its own'
args.state.tick_count = args.state.owl_line_until
OwlSpeech.expire args
check 'silent again', OwlSpeech.speaking?(args), false

puts 'text is kept on stage near the screen edges'
wide = 400.0
check 'left edge',
      OwlSpeech.label_x(0, wide), Config::OWL_SPEECH_MARGIN + (wide / 2)
check 'right edge',
      OwlSpeech.label_x(Config::SCREEN_W, wide),
      Config::SCREEN_W - Config::OWL_SPEECH_MARGIN - (wide / 2)
check 'left alone in the middle', OwlSpeech.label_x(640, wide), 640
check 'a line wider than the screen is centred',
      OwlSpeech.label_x(100, Config::SCREEN_W + 200), Config::SCREEN_W / 2.0

puts
puts $failures.zero? ? 'check_owl_speech: PASSED' : "check_owl_speech: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
