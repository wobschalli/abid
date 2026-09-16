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
      # These coordinates put lark about 5km north of campus, which I once
      # flagged as probably wrong. It is not: Lark is at 3800 Campus Suites
      # Blvd and its own listing describes it as roughly three miles north of
      # Purdue. The original row was right and the doubt was the error.
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

    # Everywhere the riders spreadsheet actually named that the list above did
    # not cover, plus the spellings people really typed into the form ('hawk',
    # 'cary nw', 'wiley sw', 'provinence', 'mccutcehon').
    #
    # Purdue-owned halls get approximate coordinates, on the same eyeballed
    # footing as the block above. The private complexes deliberately get NONE:
    # I am not confident enough about where each one sits to write a lat/lon
    # down and have it read as surveyed fact. `seed!` only fills blank
    # coordinates, `maps_token` falls back to searching the name, and
    # `rake db:geocode` resolves them properly — so nil is both honest and
    # self-correcting, where a wrong number would quietly misroute a driver.
    FROM_SPREADSHEET = [
      # --- On-campus: halls the roster named --------------------------------
      ['Hawkins Hall',      'On-campus', 40.4264, -86.9256, ['hawkins', 'hawk']],
      ['McCutcheon Hall',   'On-campus', 40.4213, -86.9250, ['mccutcheon', 'mccutcehon', 'mccutcheon hall']],
      ['Frieda Parker Hall', 'On-campus', 40.4270, -86.9150, ['frieda parker', 'freida parker', 'frieda', 'freida']],
      ['Winifred Parker Hall', 'On-campus', 40.4268, -86.9152, ['winifred parker', 'winifred', 'winnifred']],
      # Purdue's graduate and family housing, both genuinely on university land.
      ['Hilltop Apartments', 'On-campus', 40.4340, -86.9190, ['hilltop', 'hill top']],
      ['Purdue Village',    'On-campus', 40.4310, -86.9280, ['village west', 'purdue village', 'nimitz']],
      ['Third Street Suites', 'On-campus', 40.4255, -86.9260, ['third street suites', '3rd street suites']],

      # --- Chauncey / the blocks just off campus ----------------------------
      ['Campus Edge on Pierce', 'Chauncey', nil, nil, ['campus edge', 'campus edge on pierce', 'pierce']],
      ['Crosswalk Commons', 'On-campus', nil, nil, ['crosswalk', 'crosswalk commons']],
      ['Grant Street Station', 'Chauncey', nil, nil, ['grant street station', 'grant st station', 'grant']],
      ['Third and West',    'On-campus', nil, nil, ['3rd and west', '3rd & west', 'third and west', 'third & west']],
      ['Waldron Street',    'Chauncey', nil, nil, ['waldron', '221 waldron']],
      ['Brown Street',      'Chauncey', nil, nil, ['brown st', 'brown street']],
      ['Columbia Street',   'Chauncey', nil, nil, ['columbia', 'columbia st', 'columbia street']],
      ['Lincoln Street',    'Chauncey', nil, nil, ['lincoln', 'lincoln st', 'lincoln street']],
      ['Vine Street',       'Chauncey', nil, nil, ['vine', 'vine st', '4up']],
      ['Yugo River Market', 'Chauncey', nil, nil, ['yugo', 'river market', 'yugo west lafayette river market']],
      ['Riverbend Apartments', 'Chauncey', nil, nil, ['riverbend', 'riverbend apts', 'river road']],

      # --- Northwestern -----------------------------------------------------
      ['Alight West Lafayette', 'Northwestern', nil, nil, ['alight', 'the cottages']],
      ['Benchmark Apartments', 'Chauncey', nil, nil, ['benchmark', 'benchmark ii', 'benchmark iii']],

      # --- Klondike ---------------------------------------------------------
      ['Provenance',        'Klondike', nil, nil, ['provenance', 'provinence', 'provinance', 'provenance apt']]
    ].freeze

    # Street addresses, taken from each property's own listing and verified by
    # geocoding them — every one below resolves inside Tippecanoe County.
    #
    # This is what makes a place findable. OpenStreetMap has never heard of
    # "Third and West" or "Alight West Lafayette"; querying them unbounded
    # returns nothing at all. It knows the streets they stand on perfectly well.
    #
    # Streets are their own address, and the Purdue halls resolve by name, so
    # only the named properties need an entry here.
    ADDRESSES = {
      # Purdue-owned
      'Third and West' => '1401 3rd Street',
      'Aspire at Discovery Park' => '1245 W State Street',
      # Private complexes
      'lark' => '3800 Campus Suites Boulevard',
      'Alight West Lafayette' => '2243 Sagamore Parkway West',
      'Benchmark Apartments' => '421 S Chauncey Avenue',
      'Yugo River Market' => '221 E State Street',
      'Provenance' => '1501 Mitch Daniels Boulevard',
      'Rise on Chauncey' => '100 S Chauncey Avenue',
      'Campus Edge on Pierce' => '134 Pierce Street',
      'Crosswalk Commons' => '925 Hilltop Drive',
      'Grant Street Station' => '320 S Grant Street',
      'Fuse' => '720 Northwestern Avenue',
      'Hub on State' => '111 S Salisbury Street',
      'Riverbend Apartments' => '202 S River Road'
    }.freeze

    # Spellings for places that already exist above. Folded in by `seed!` so a
    # form answer of 'cary nw' or 'honors south' resolves instead of silently
    # creating a duplicate row with no zone.
    EXTRA_ALIASES = {
      'Cary Quadrangle' => ['cary nw', 'cary east', 'cary west', 'cary south', 'cary northwest'],
      'Wiley Hall' => ['wiley sw', 'wiley southwest'],
      'Honors College' => ['honors south', 'honors north', 'honors college south'],
      'Earhart Hall' => ['earhart hall'],
      'Tarkington Hall' => ['tarkington hall'],
      'Harrison Hall' => ['harrison hall'],
      'Meredith South' => ['meredith south hall'],
      'lark' => ['apt lark', 'lark apt'],
      'Aspire at Discovery Park' => ['aspire apartments', 'aspire apts'],
      'Fuse' => ['fuse apts'],
      'Rise on Chauncey' => ['rise on chauncey apartments'],
      'Shreve Hall' => ['shreve hall'],
      'Owen Hall' => ['owen hall'],
      'Hillenbrand Hall' => ['hillenbrand hall'],
      'Windsor Halls' => ['windsor hall']
    }.freeze

    ALL = (EXISTING + PLACES + FROM_SPREADSHEET).freeze

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

      # Street addresses, looked up from the property's own listing. A name is
      # not a map feature — OpenStreetMap has never heard of "Third and West" —
      # so these are what makes a place findable.
      ADDRESSES.each do |name, address|
        location = Location.find_by(name: name) or next

        location.update!(address: address)
      end

      EXTRA_ALIASES.each do |name, aliases|
        location = Location.find_by(name: name) or next

        location.update!(aliases: (location.aliases.to_a | aliases).uniq)
      end
    end

    def count
      ALL.size
    end
  end
end
