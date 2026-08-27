require_relative '../../app/config.rb'
require_relative '../../app/world.rb'
require_relative '../../app/regions.rb'
require_relative '../../app/owl_speech.rb'

# Minimal stand-in for DragonRuby's args.state, which is an open structure.
class FakeState
  attr_accessor :resolved_regions, :tick_count,
                :owl_last_region, :owl_line, :owl_line_until, :owl_said

  def initialize
    @resolved_regions = []
    @tick_count       = 0
    @owl_line_until   = 0
    @owl_said         = []
    @player           = FakePlayer.new
  end

  attr_reader :player
end

class FakePlayer
  attr_accessor :x, :depth

  def initialize
    @x     = 0
    @depth = 0.0
  end
end

class FakeArgs
  attr_reader :state

  def initialize
    @state = FakeState.new
  end

  # Walk the player to a spot and run one tick of the owl's update.
  def step x, depth
    @state.player.x     = x
    @state.player.depth = depth
    @state.tick_count  += 1
    OwlSpeech.update self
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

# Two authored positions, taken from Regions rather than hardcoded, so this
# check follows the map if the map moves.
FERN  = [100, 40.0]    # :fern_hollow
EAST  = [900, 40.0]    # :east_clearing
WILD  = [640, 40.0]    # the uncovered corridor -- :wilds

puts 'the fixtures sit where this check assumes they do'
check 'fern',  Regions.at(*FERN)[:name],  :fern_hollow
check 'east',  Regions.at(*EAST)[:name],  :east_clearing
check 'wilds', Regions.at(*WILD)[:name],  Regions::WILDS[:name]

puts 'loading the file runs assert_triggers_name_real_lines!'
check 'every trigger names a real line',
      OwlSpeech::TRIGGERS.values.all? { |id| OwlSpeech::LINES.key? id }, true

puts 'standing somewhere is not entering it'
args = FakeArgs.new
args.step(*FERN)
check 'silent on the first frame', OwlSpeech.speaking?(args), false

puts 'crossing into an unresolved region speaks'
args.step(*EAST)
check 'speaking',        OwlSpeech.speaking?(args), true
check 'the right line',  args.state.owl_line, :fool_reaches
check 'logged',          args.state.owl_said, [:fool_reaches]

puts 'it finishes its thought rather than being interrupted'
args.step(*FERN)
check 'still the first firing', args.state.owl_said, [:fool_reaches]

puts 'the line expires on its own'
args.state.tick_count = args.state.owl_line_until
OwlSpeech.expire args
check 'silent again', OwlSpeech.speaking?(args), false

puts 'a recurring line may fire again, and every firing is logged'
args.state.owl_last_region = :fern_hollow
args.step(*EAST)
check 'speaking again', OwlSpeech.speaking?(args), true
check 'both firings recorded', args.state.owl_said, [:fool_reaches, :fool_reaches]

puts 'the wilds never triggers -- it can never resolve'
args = FakeArgs.new
args.step(*FERN)
args.step(*WILD)
check 'silent in the corridor', OwlSpeech.speaking?(args), false

puts 'a resolved region does not trigger'
args = FakeArgs.new
args.state.resolved_regions = [:east_clearing]
args.step(*FERN)
args.step(*EAST)
check 'silent where the truth is known', OwlSpeech.speaking?(args), false

puts 'staying put does not re-trigger'
args = FakeArgs.new
args.step(*FERN)
args.step(*EAST)
args.state.owl_line = nil               # pretend the line has expired
args.step(920, 45.0)                    # still :east_clearing
check 'silent while inside the same region', OwlSpeech.speaking?(args), false

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
