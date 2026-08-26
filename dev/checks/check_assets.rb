require_relative '../../app/config.rb'
require_relative '../../app/assets.rb'

$failures = 0

def check label, got, want
  if got == want
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want #{want.inspect})"
    $failures += 1
  end
end

def check_close label, got, want, tolerance = 0.01
  if (got - want).abs < tolerance
    puts "  PASS  #{label}"
  else
    puts "  FAIL  #{label}  (got #{got.inspect}, want ~#{want.inspect})"
    $failures += 1
  end
end

# Paths in the table are relative to the game directory, which is two levels up.
GAME_DIR = File.expand_path '../..', __dir__

puts 'every declared frame file exists on disk'
Assets::TABLE.each do |name, tiers|
  tiers.each do |tier, descriptor|
    descriptor[:paths].each do |path|
      check "#{name}/#{tier} #{path}", File.exist?(File.join(GAME_DIR, path)), true
    end
  end
end

puts 'frame count matches declared frames'
Assets::TABLE.each do |name, tiers|
  tiers.each do |tier, descriptor|
    check "#{name}/#{tier} path count", descriptor[:paths].length, descriptor[:frames]
  end
end

puts 'progress maps across the whole cycle'
frames = Assets.descriptor(:player_walk, :myth)[:frames]
check 'progress 0.0',        Assets.frame_path(:player_walk, :myth, 0.0),  'sprites/player/myth/frame_000.png'
check 'progress 0.5',        Assets.frame_path(:player_walk, :myth, 0.5),  "sprites/player/myth/frame_00#{frames / 2}.png"
check 'progress 0.99',       Assets.frame_path(:player_walk, :myth, 0.99), "sprites/player/myth/frame_00#{frames - 1}.png"
check 'progress 1.0 clamps', Assets.frame_path(:player_walk, :myth, 1.0),  "sprites/player/myth/frame_00#{frames - 1}.png"

puts 'unauthored tier falls back to myth'
check 'truth falls back', Assets.descriptor(:player_walk, :truth), Assets.descriptor(:player_walk, :myth)

puts 'geometry'
check_close 'foot pad ratio', Assets.foot_pad_ratio(:player_walk, :myth), 7.0 / 40

w, h = Assets.draw_size :player_walk, :myth
check_close 'draw width',  w, 138.46
check_close 'draw height', h, 138.46

puts 'figure height is identical across every declared tier'
Assets::TABLE.each do |name, tiers|
  tiers.each_key do |tier|
    _, drawn_h = Assets.draw_size name, tier
    descriptor = Assets.descriptor name, tier
    figure_px  = drawn_h * descriptor[:figure_h] / descriptor[:canvas_h]
    check_close "#{name}/#{tier} figure px", figure_px, Config::CHARACTER_HEIGHT_PX
  end
end

puts
puts $failures.zero? ? 'check_assets: PASSED' : "check_assets: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
