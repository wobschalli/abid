require_relative 'components'

# Chrome-less shell for pages shown before you are signed in. Same palette and
# type as Components::Layout — just no nav.
class Components::SkinnyLayout < Phlex::HTML
  def initialize(title: 'abid')
    @title = title
  end

  def view_template(&)
    head do
      title { @title }
      meta name: 'viewport', content: 'width=device-width, initial-scale=1'
      link rel: 'preconnect', href: 'https://fonts.googleapis.com'
      link rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: true
      link rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500;600&family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700&display=swap'
      link href: url('css/application.min.css'), type: 'text/css', rel: 'stylesheet'
      script src: url('js/application.min.js')
    end

    body(class: 'bg-surface-board text-ink font-sans antialiased min-h-screen', data_root: url('/', false).chomp('/')) do
      div(class: 'relative min-h-screen flex items-center justify-center p-5') do
        theme_toggle
        div(class: 'w-full max-w-sm') { yield }
      end
    end
  end

  private

  def theme_toggle
    button(
      id: 'theme-toggle', type: 'button', title: 'Switch theme',
      class: 'absolute top-4 right-4 p-2 rounded-lg text-ink/60 hover:text-ink hover:bg-ink/5 cursor-pointer'
    ) do
      render Components::Layout::ThemeIcon.new(
        id: 'theme-toggle-dark-icon',
        d: 'M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z'
      )
      render Components::Layout::ThemeIcon.new(
        id: 'theme-toggle-light-icon', fill_clip_rule: 'evenodd',
        d: 'M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z'
      )
    end
  end
end
