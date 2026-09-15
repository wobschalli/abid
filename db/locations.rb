# Real West Lafayette / Purdue geography.
#
# Deliberately its own file rather than living in one of the two seed scripts:
#   - db/seeds.rb exits at the top when config.yml is absent, and config.yml is
#     gitignored — so on any machine without Discord credentials, including CI,
#     these rows would never be created.
#   - db/demo_seeds.rb destroys and rebuilds its rows on every run. Real places
#     must not live in a destroy-and-rebuild file.
#
# COORDINATES ARE APPROXIMATE — good to roughly a block, eyeballed rather than
# surveyed. They exist so the Google Maps link in a driver's DM has a precise
# origin instead of a text search. Run `rake db:geocode` to refine them against
# Nominatim, and correct anything that looks wrong: `seed!` only fills blank
# coordinates, so a hand-corrected lat/lon survives every later run.
module Abid
  module Locations
    GLCAC = 'greater lafayette chinese alliance church'.freeze

    # The two rows db/seeds.rb has always created. Coordinates left exactly as
    # they were — this is live data; the only thing being added is a zone.
    EXISTING = [
      # NOTE: these coordinates put 'lark' about 5km north of campus, which is
      # not where the Chauncey-area Lark most people mean actually is. Zoned to
      # match the coordinates that exist rather than silently moving a
      # production row. Worth a human check.
      ['lark', 'Northwestern', 40.4729654, -86.9467261,
       ['lark apartments', 'lark apts', 'lark west lafayette']],
      [GLCAC, 'Klondike', 40.4521281, -86.9720287,
       ['glcac', 'chinese alliance church', 'church']]
    ].freeze

    # name, zone, lat, lon, aliases (all lowercase — matching is
    # case-insensitive, and these are the spellings people actually type)
    PLACES = [
      # --- On-campus: residence halls ------------------------------------
      ['Cary Quadrangle',       'On-campus', 40.4278, -86.9210, ['cary', 'cary quad', 'cary hall']],
      ['Earhart Hall',          'On-campus', 40.4232, -86.9200, ['earhart', 'earheart']],
      ['Hillenbrand Hall',      'On-campus', 40.4220, -86.9245, ['hillenbrand', 'hille']],
      ['Wiley Hall',            'On-campus', 40.4246, -86.9232, ['wiley']],
      ['Windsor Halls',         'On-campus', 40.4266, -86.9146, ['windsor', 'duhme', 'wood hall']],
      ['Owen Hall',             'On-campus', 40.4230, -86.9230, ['owen']],
      ['Tarkington Hall',       'On-campus', 40.4235, -86.9222, ['tarkington', 'tark']],
      ['Harrison Hall',         'On-campus', 40.4226, -86.9237, ['harrison']],
      ['Meredith Hall',         'On-campus', 40.4262, -86.9160, ['meredith', 'meredith north']],
      ['Meredith South',        'On-campus', 40.4228, -86.9265, ['meredith south', 'mesh']],
      ['Shreve Hall',           'On-campus', 40.4218, -86.9218, ['shreve']],
      ['First Street Towers',   'On-campus', 40.4213, -86.9204, ['first street towers', 'fst', '1st street towers']],
      ['Honors College',        'On-campus', 40.4243, -86.9183, ['honors', 'honors college and residences', 'hcrs']],
      ['Purdue Memorial Union', 'On-campus', 40.4246, -86.9114, ['pmu', 'union', 'memorial union']],

      # --- Chauncey / the Village ----------------------------------------
      ['Chauncey Hill',         'Chauncey', 40.4238, -86.9072, ['chauncey', 'chauncey hill mall', 'the village', 'village']],
      ['Rise on Chauncey',      'Chauncey', 40.4229, -86.9080, ['rise', 'the rise']],
      ['Hub on State',          'Chauncey', 40.4247, -86.9078, ['hub', 'the hub', 'hub on campus']],
      ['Fuse',                  'Chauncey', 40.4265, -86.9103, ['the fuse', 'fuse apartments']],
      ['Wabash Landing',        'Chauncey', 40.4215, -86.9020, ['landing', 'wabash landing']],
      ['State Street',          'Chauncey', 40.4243, -86.9090, ['state st', 'state']],

      # --- Northwestern corridor ------------------------------------------
      ['Lindberg Village',      'Northwestern', 40.4380, -86.9110, ['lindberg', 'lindberg road', 'lindberg rd']],
      ['Salisbury Street',      'Northwestern', 40.4290, -86.9243, ['salisbury', 'salisbury st']],
      ['Cumberland Avenue',     'Northwestern', 40.4482, -86.9245, ['cumberland', 'cumberland ave']],
      ['Sagamore Parkway West', 'Northwestern', 40.4470, -86.9130, ['sagamore', 'sagamore pkwy', 'sagamore parkway']],
      ['Williamsburg on the Wabash', 'Northwestern', 40.4330, -86.9050, ['williamsburg', 'williamsburg apartments']],

      # --- Klondike / west ------------------------------------------------
      ['Klondike Road',         'Klondike', 40.4480, -86.9540, ['klondike', 'klondike rd']],
      ['McCormick Road',        'Klondike', 40.4200, -86.9420, ['mccormick', 'mccormick rd']],
      ['Purdue West',           'Klondike', 40.4230, -86.9420, ['purdue west', 'purdue west plaza', 'pw']],
      ['Blackbird Farms',       'Klondike', 40.4470, -86.9470, ['blackbird', 'blackbird farms apartments']],
      ['Yeager Road',           'Klondike', 40.4420, -86.9370, ['yeager', 'yeager rd']],
      # Discovery Park District is southwest off US-231, so geographically this
      # sits with Klondike rather than the Village despite the name.
      ['Aspire at Discovery Park', 'Klondike', 40.4140, -86.9380, ['aspire', 'discovery park']],

      # --- Lafayette, across the Wabash -----------------------------------
      ['Downtown Lafayette',    'Lafayette', 40.4167, -86.8753, ['downtown', 'courthouse', 'main street']],
      ['Market Square',         'Lafayette', 40.4200, -86.8750, ['market square', 'market sq']],
      ['Columbian Park',        'Lafayette', 40.4090, -86.8680, ['columbian', 'columbian park']],
      ['Creasy Lane',           'Lafayette', 40.4080, -86.8480, ['creasy', 'creasy ln', 'pavilions']],
      ['Elston Road',           'Lafayette', 40.4300, -86.8800, ['elston', 'elston rd']]
    ].freeze

    ALL = (EXISTING + PLACES).freeze

    module_function

    # Idempotent and non-destructive:
    #   - zone is always set (that is the point of this file)
    #   - coordinates are only filled when blank, so a correction survives
    #   - aliases are unioned, never replaced
    def seed!
      ALL.each do |name, zone, lat, lon, aliases|
        location = Location.find_or_initialize_by(name: name)
        location.zone = zone
        location.lat = lat if location.lat.blank?
        location.lon = lon if location.lon.blank?
        location.aliases = (location.aliases.to_a | aliases).uniq
        location.save! # bang: a zone typo here must not seed silently
      end
    end

    def count
      ALL.size
    end
  end
end
