require_relative 'components'

class Components::Layout < Phlex::HTML
  def initialize(title:'abid', leader:false)
    @title = title
    @leader = leader
  end

  def view_template(&)
    head do
      title { @title }
      link href: url('css/application.min.css'), type: 'text/css', rel: 'stylesheet'
      script src: url('js/application.min.js')
    end

    body class: 'bg-white dark:bg-gray-900' do
      nav class: 'fixed top-0 z-50 w-full bg-white border-b border-gray-200 dark:bg-gray-800 dark:border-gray-700' do
        div class: 'px-3 py-3 lg:px-5 lg:pl-3' do
          div class: 'flex items-center justify-between' do
            div class: 'flex items-center justify-start rtl:justify-end' do
              button data_drawer_target: 'sidebar', data_drawer_toggle: 'sidebar', aria_controls: 'sidebar', type: 'button', class: 'inline-flex items-center p-2 text-sm text-gray-500 rounded-lg sm:hidden hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:text-gray-400 dark:hover:bg-gray-700 dark:focus:ring-gray-600' do
                span(class: 'sr-only') { 'Open sidebar' }
                render Components::Icon.new(ahid: true, fill_rule: 'evenodd', clip_rule: 'evenodd', d: 'M2 4.75A.75.75 0 012.75 4h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 4.75zm0 10.5a.75.75 0 01.75-.75h7.5a.75.75 0 010 1.5h-7.5a.75.75 0 01-.75-.75zM2 10a.75.75 0 01.75-.75h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 10z')
              end
              a href: url('/'), class: 'flex ms-2 md:me-24 max-w-8 max-h-12' do
                img src: url('logo.webp'), class: 'me-3', alt: 'Abide logo'
                span(class: 'self-center text-xl font-semibold sm:text-2xl whitespace-nowrap dark:text-white') { 'Abid' }
              end
            end
            div class: 'flex items-center' do
              div class: 'flex items-center ms-3' do
                button id: 'theme-toggle', type: 'button', class: 'text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 focus:outline-none focus:ring-4 focus:ring-gray-200 dark:focus:ring-gray-700 rounded-lg text-sm p-2.5' do
                  render LayoutSVG.new(id: 'theme-toggle-dark-icon', d: 'M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z')
                  render LayoutSVG.new(id: 'theme-toggle-light-icon', fill_clip_rule: 'evenodd',
                    d: 'M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z'
                  )
                end
              end
            end
          end
        end
      end
      aside id: 'sidebar', aria_label: 'Sidebar', class: 'fixed top-0 left-0 z-40 w-64 h-screen pt-20 transition-transform -translate-x-full bg-white border-r border-gray-200 sm:translate-x-0 dark:bg-gray-800 dark:border-gray-700' do
        div class: 'h-full px-3 pb-4 overflow-y-auto bg-white dark:bg-gray-800' do
          ul class: 'space-y-2 font-medium' do
            sidenav text: 'Events', href: url('/events')
            sidenav text: 'Locations', href: url('/locations')
            sidenav text: 'Users', href: url('/users')
          end
          ul class: 'pt-4 mt-4 space-y-2 font-medium border-t border-gray-200 dark:border-gray-700' do
            sidenav text: 'Logout', href: url('/logout')
          end
        end
      end
      main class: 'p-4 sm:ml-64' do
        div class: 'p-4 mt-14' do
          yield
        end
      end
    end
  end

  private
  class LayoutSVG < Phlex::SVG
    def initialize(id:'', d:'', fill_clip_rule:'')
      @id = id
      @d = d
      @fill_clip_rule = fill_clip_rule
    end

    def view_template
      svg id: @id, class: 'hidden w-5 h-5', fill: 'currentColor', viewBox: '0 0 20 20', xmlns: 'http://www.w3.org/2000/svg' do
        path d: @d, fill_rule: @fill_clip_rule, clip_rule: @fill_clip_rule
      end
    end
  end

  def sidenav(svg:LayoutSVG.new(), text:'', href:'')
    li do
      a href: href, class: 'flex items-center p-2 text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group' do
        render svg
        span(class: 'ms-3') { text }
      end
    end
  end
end
