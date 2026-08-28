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

puts 'path count matches whichever way the descriptor names its files'
Assets::TABLE.each do |name, tiers|
  tiers.each do |tier, descriptor|
    expected = descriptor[:files] ? descriptor[:files].length : descriptor[:frames]
    check "#{name}/#{tier} path count", descriptor[:paths].length, expected
  end
end

# A descriptor that declares neither, or both, would silently produce the wrong
# path list rather than failing, so it is rejected outright.
puts 'every descriptor names its files exactly one way'
Assets::TABLE.each do |name, tiers|
  tiers.each do |tier, descriptor|
    named = [descriptor[:frames], descriptor[:files]].compact.length
    check "#{name}/#{tier} naming", named, 1
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

puts 'push poses are two-frame cycles, and progress moves through them'
#
# They used to be single held frames, with a faked sine bob standing in for
# footfall. The stride art replaced both, so progress must now actually
# advance -- a pose that ignored it would put him back to sliding.
Assets::PUSH_POSE_FILES.each_key do |name|
  check "#{name} path count", Assets.descriptor(name, :myth)[:paths].length, 2
  check "#{name} progress advances",
        Assets.frame_path(name, :myth, 0.0) == Assets.frame_path(name, :myth, 0.99),
        false
end

check_close 'push foot pad ratio', Assets.foot_pad_ratio(:player_push_east, :myth), 3.0 / 32

puts 'the traveller still uses the shared character height'
[:player_walk, :player_push_east, :player_push_north].each do |name|
  check "#{name} declares no height of its own",
        Assets.descriptor(name, :myth)[:height_px], nil
end

puts 'every asset draws its figure at the height it asks for, in every tier'
#
# The point of this is tier INDEPENDENCE: myth and truth art may be authored on
# different canvases with different proportions, and must still come out the
# same size on screen. `height_px` lets an asset name that size for itself --
# an owl is not person-sized -- and defaults to CHARACTER_HEIGHT_PX, so
# anything that does not say otherwise is still checked against it.
Assets::TABLE.each do |name, tiers|
  tiers.each_key do |tier|
    _, drawn_h = Assets.draw_size name, tier
    descriptor = Assets.descriptor name, tier
    figure_px  = drawn_h * descriptor[:figure_h] / descriptor[:canvas_h]
    target     = descriptor[:height_px] || Config::CHARACTER_HEIGHT_PX
    check_close "#{name}/#{tier} figure px", figure_px, target
  end
end

puts
puts $failures.zero? ? 'check_assets: PASSED' : "check_assets: #{$failures} FAILED"
exit($failures.zero? ? 0 : 1)
