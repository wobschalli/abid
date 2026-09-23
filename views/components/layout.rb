require_relative 'components'

# The application shell.
#
# Uses the same semantic palette as the ride board — surface / ink / line /
# accent, flipped wholesale in .dark — rather than the Flowbite gray scale it
# started with. Two palettes side by side read as two different applications
# bolted together, which is exactly what it looked like.
class Components::Layout < Phlex::HTML
  # text, href, and the path prefix that marks the entry active.
  NAV = [
    ['Ride board', '/board', '/board'],
    # Events, Series and Sign-ups were three entries over the same rows.
    ['Schedule', '/schedule', '/schedule'],
    ['Locations', '/locations', '/locations'],
    ['Members', '/users', '/users']
  ].freeze

  # full_bleed: the ride board manages its own scrolling and fills the viewport,
  # so it opts out of the padded main container.
  def initialize(title: 'abid', leader: false, full_bleed: false, path: nil)
    @title = title
    @leader = leader
    @full_bleed = full_bleed
    @path = path || Abid.current_path
  end

  def view_template(&)
    head do
      title { @title }
      meta name: 'viewport', content: 'width=device-width, initial-scale=1'
      link rel: 'preconnect', href: 'https://fonts.googleapis.com'
      link rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: true
      link rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500;600&family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700&display=swap'
      link href: url('css/leaflet.css'), type: 'text/css', rel: 'stylesheet'
      link href: url('css/application.min.css'), type: 'text/css', rel: 'stylesheet'
      # Intentionally render-blocking: darkmode.js sets the .dark class before
      # first paint, and deferring it reintroduces a flash of the light theme.
      script src: url('js/application.min.js')
    end

    body(class: 'bg-surface-board text-ink font-sans antialiased', data_root: url('/', false).chomp('/')) do
      topbar
      sidebar
      content(&)
    end
  end

  private

  def topbar
    nav(class: 'fixed top-0 z-50 w-full h-14 bg-surface border-b border-line') do
      div(class: 'h-full px-3 flex items-center gap-2') do
        drawer_toggle
        brand
        div(class: 'flex-1')
        theme_toggle
      end
    end
  end

  def drawer_toggle
    button(
      type: 'button',
      data_drawer_target: 'sidebar', data_drawer_toggle: 'sidebar', aria_controls: 'sidebar',
      class: 'sm:hidden inline-flex items-center p-2 rounded-lg text-ink/70 hover:bg-ink/5 cursor-pointer'
    ) do
      span(class: 'sr-only') { 'Open sidebar' }
      render Components::Icon.new(
        ahid: true, klass: 'w-5 h-5', fill_rule: 'evenodd', clip_rule: 'evenodd',
        d: 'M2 4.75A.75.75 0 012.75 4h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 4.75zm0 10.5a.75.75 0 01.75-.75h7.5a.75.75 0 010 1.5h-7.5a.75.75 0 01-.75-.75zM2 10a.75.75 0 01.75-.75h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 10z'
      )
    end
  end

  def brand
    a(href: url('/'), class: 'flex items-center gap-2 no-underline text-ink') do
      img src: url('logo.webp'), alt: '', class: 'w-6 h-6 object-contain'
      span(class: 'font-display font-bold text-lg -tracking-[.015em]') { 'Abid' }
    end
  end

  def theme_toggle
    button(
      id: 'theme-toggle', type: 'button',
      title: 'Switch theme',
      class: 'p-2 rounded-lg text-ink/60 hover:text-ink hover:bg-ink/5 cursor-pointer'
    ) do
      render ThemeIcon.new(id: 'theme-toggle-dark-icon',
                           d: 'M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z')
      render ThemeIcon.new(id: 'theme-toggle-light-icon', fill_clip_rule: 'evenodd',
                           d: 'M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z')
    end
  end

  def sidebar
    aside(
      id: 'sidebar', aria_label: 'Sidebar',
      class: 'fixed top-14 left-0 z-40 w-60 h-[calc(100vh-3.5rem)] bg-surface-sunk border-r border-line ' \
             'transition-transform -translate-x-full sm:translate-x-0'
    ) do
      div(class: 'h-full px-3 py-4 overflow-y-auto flex flex-col') do
        ul(class: 'flex flex-col gap-0.5') { NAV.each { |text, href, prefix| sidenav(text, href, prefix) } }
        div(class: 'flex-1')
        ul(class: 'pt-3 border-t border-line') { sidenav('Log out', '/logout', nil) }
      end
    end
  end

  # The active entry gets a tinted pill and an accent rule, so it is obvious
  # where you are without reading the URL.
  def sidenav(text, href, prefix)
    active = prefix.present? && @path.to_s.start_with?(prefix)

    li do
      a(
        href: url(href),
        aria_current: (active ? 'page' : nil),
        class: [
          'flex items-center gap-2 px-3 py-2 rounded-lg text-[13px] font-medium no-underline transition-colors',
          active ? 'bg-accent-tint text-accent' : 'text-ink/75 hover:text-ink hover:bg-ink/5'
        ].join(' ')
      ) do
        span(class: "w-[3px] h-4 rounded-full flex-none #{active ? 'bg-accent' : 'bg-transparent'}")
        plain text
      end
    end
  end

  def content(&)
    main(class: "sm:ml-60 mt-14 #{'min-h-[calc(100vh-3.5rem)]' unless @full_bleed}") do
      if @full_bleed
        yield
      else
        div(class: 'p-4 sm:p-6') { yield }
      end
    end
  end

  class ThemeIcon < Phlex::SVG
    def initialize(id: '', d: '', fill_clip_rule: '')
      @id = id
      @d = d
      @fill_clip_rule = fill_clip_rule
    end

    def view_template
      svg(id: @id, class: 'hidden w-5 h-5', fill: 'currentColor', viewBox: '0 0 20 20',
          xmlns: 'http://www.w3.org/2000/svg') do
        path d: @d, fill_rule: @fill_clip_rule, clip_rule: @fill_clip_rule
      end
    end
  end
end
